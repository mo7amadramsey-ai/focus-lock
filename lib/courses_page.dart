import 'flavor.dart';
import 'package:flutter/material.dart';
import 'course_download.dart';
import 'doc_open.dart';
import 'link_open.dart';
import 'links_page.dart';
import 'lock_modes.dart';
import 'moodle_page.dart';
import 'shell.dart';
import 'study.dart';
import 'study_page.dart';
import 'theme.dart';

/// Courses: what you see on Moodle, but simple. Sections in order, every file / video / link opens inside the app.
class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key});
  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  String q = '';

  Future<void> _sync() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const MoodlePage(autoSync: true)));
    await study.load();
    study.fetchDurations();
  }

  @override
  Widget build(BuildContext c) => AnimatedBuilder(
        animation: study,
        builder: (_, __) {
          final ids = study.courseIds().where((id) => q.isEmpty || (study.courses[id] ?? '').toLowerCase().contains(q.toLowerCase())).toList();
          return Scaffold(
            appBar: topBar(c, 'المواد', extra: [IconButton(tooltip: 'مزامنة المودل', icon: const Icon(Icons.sync_rounded), onPressed: _sync)]),
            body: study.links.isEmpty
                ? emptyStudy(c)
                : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
                    TextField(onChanged: (v) => setState(() => q = v.trim()), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث عن مادة')),
                    if (study.lastSync != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                        child: Text('آخر مزامنة: ${dayLabel(study.lastSync!)} ${clock(study.lastSync!)}', style: TextStyle(color: kMuted, fontSize: 12.5)),
                      ),
                    const SizedBox(height: 6),
                    for (final id in ids) _card(c, id),
                  ]),
          );
        },
      );

  Widget _card(BuildContext c, String id) {
    final total = study.totalOf(id), done = study.doneOf(id);
    final und = study.understandingCourse(id);
    final tasks = study.tasks.where((t) => t.cid == id && !study.taskDone(t)).length;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => CourseDetailPage(cid: id))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(study.courses[id] ?? 'مادة $id', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: total == 0 ? 0 : done / total, minHeight: 7)),
            const SizedBox(height: 8),
            Text(
                '$done/$total منجز${und != null ? ' · الفهم ${(und * 100).round()}%' : ''}${tasks > 0 ? ' · $tasks تسليم/اختبار' : ''}',
                style: TextStyle(color: kMuted, fontSize: 12.5)),
          ]),
        ),
      ),
    );
  }
}

/// One course: its tasks and its sections with everything inside, like on Moodle
class CourseDetailPage extends StatelessWidget {
  final String cid;
  const CourseDetailPage({super.key, required this.cid});

  static const _typeName = {'yt': 'فيديو', 'video': 'فيديو', 'pdf': 'PDF', 'doc': 'مستند', 'file': 'ملف', 'ext': 'رابط', 'act': 'صفحة'};

  void _open(BuildContext c, MoodleLink l) => openLinkInApp(c, url: l.url, title: l.title, group: l.group, onOpenDoc: (u) => openMoodleDocument(c, u));

  @override
  Widget build(BuildContext c) => AnimatedBuilder(
        animation: study,
        builder: (_, __) {
          final links = study.links.where((l) => l.cid == cid).toList();
          final secs = <String>[];
          for (final l in links) {
            if (!secs.contains(l.sec)) secs.add(l.sec);
          }
          final tasks = study.agenda().where((a) => a.cid == cid).toList();
          final undone = links.where((l) => ytId(l) != null && !study.isDone(l)).toList();
          final total = study.totalOf(cid), done = study.doneOf(cid);
          return Scaffold(
            appBar: AppBar(
              title: Text(study.courses[cid] ?? 'مادة', maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  tooltip: 'جلسة قفل على فيديوهات المادة',
                  icon: const Icon(Icons.lock_outline_rounded),
                  onPressed: () => startPlaylistLock(c, undone),
                ),
                IconButton(tooltip: 'تنزيل المادة (فيديوهات وملفات)', icon: const Icon(Icons.download_rounded), onPressed: () => downloadCourse(c, cid)),
              ],
            ),
            body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${total == 0 ? 0 : (done * 100 / total).round()}% منجز', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 8),
                    ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: total == 0 ? 0 : done / total, minHeight: 8)),
                    const SizedBox(height: 6),
                    Text('$done من $total', style: TextStyle(color: kMuted)),
                  ]),
                ),
              ),
              if (tasks.isNotEmpty) ...[
                Padding(padding: const EdgeInsets.fromLTRB(4, 14, 4, 4), child: Text('التسليمات والاختبارات', style: TextStyle(fontWeight: FontWeight.w800, color: kAccent))),
                for (final a in tasks) agendaTile(a),
              ],
              const SizedBox(height: 8),
              for (var i = 0; i < secs.length; i++) _section(c, links, secs, i),
            ]),
          );
        },
      );

  Widget _section(BuildContext c, List<MoodleLink> links, List<String> secs, int i) {
    final items = links.where((l) => l.sec == secs[i]).toList();
    final cnt = items.where(countable).toList();
    return Card(
      child: ExpansionTile(
        key: ValueKey('sec$cid$i'),
        initiallyExpanded: i == 0,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(secs[i].isEmpty ? 'عام' : secs[i], style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${cnt.where(study.isDone).length}/${cnt.length} منجز', style: TextStyle(color: kMuted, fontSize: 12.5)),
        children: [for (final l in items) _item(c, l)],
      ),
    );
  }

  Widget _item(BuildContext c, MoodleLink l) {
    if (l.group == 'txt') {
      // text the teacher wrote on the course page
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.notes, size: 18, color: kMuted),
          const SizedBox(width: 10),
          Expanded(child: SelectableText(l.title, style: TextStyle(color: kSoft, height: 1.6))),
        ]),
      );
    }
    final isC = countable(l);
    final id = ytId(l);
    return ListTile(
      dense: true,
      leading: isC
          ? Checkbox(value: study.isDone(l), onChanged: (_) => study.toggleDone(l))
          : Padding(padding: const EdgeInsets.all(12), child: Icon(groupIcon(l.group), size: 20)),
      title: Text(l.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Row(children: [
        Icon(groupIcon(l.group), size: 14, color: l.group == 'yt' ? kAccent : kMuted),
        const SizedBox(width: 4),
        Text('${_typeName[l.group] ?? ''}${id != null && study.dur.containsKey(id) ? ' · ${(study.dur[id]! / 60).ceil()} د' : ''}', style: TextStyle(color: kMuted, fontSize: 12)),
      ]),
      trailing: isC ? IconButton(tooltip: 'الدفتر', icon: Icon(Icons.edit_note, color: (study.noteOf(l)?.isEmpty ?? true) ? null : kAccent), onPressed: () => openNotebook(c, l)) : null,
      onTap: () => _open(c, l),
      onLongPress: () => showLinkActions(c, url: l.url, title: l.title, group: l.group, onOpenDoc: (u) => openMoodleDocument(c, u)),
    );
  }
}
