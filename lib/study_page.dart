import 'package:flutter/material.dart';
import 'links_page.dart';
import 'lock_modes.dart';
import 'lock_setup.dart';
import 'moodle_page.dart';
import 'notebook_page.dart';
import 'preview_page.dart';
import 'study.dart';
import 'theme.dart';

/// Private study mentor, all local: plan until the deadline, progress per course, lecture notebook + quizzes.
class StudyPage extends StatefulWidget {
  const StudyPage({super.key});
  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  @override
  void initState() {
    super.initState();
    study.load().then((_) => study.fetchDurations());
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: study.deadline.isBefore(now) ? now : study.deadline,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
      helpText: 'موعد إنهاء كل المواد',
    );
    if (d != null) study.setDeadline(d);
  }

  void _play(MoodleLink l) {
    final id = ytId(l);
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => PreviewPage(url: l.url, title: l.title, youtubeId: id)));
  }

  void _notebook(MoodleLink l) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => NotebookPage(link: l)));

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.travel_explore, size: 56, color: Colors.white38),
            const SizedBox(height: 12),
            const Text('لا توجد روابط بعد. افتح المودل واضغط أيقونة الروابط 🔗 ثم «ابدأ استخراج الروابط».',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, height: 1.6)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MoodlePage())),
              icon: const Icon(Icons.school),
              label: const Text('فتح المودل'),
            ),
          ]),
        ),
      );

  String _dayLabel(PlanDay d) {
    final now = DateTime.now();
    final diff = d.date.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (diff == 0) return 'اليوم';
    if (diff == 1) return 'غداً';
    return '${dayName(d.date)} ${d.date.day}/${d.date.month}';
  }

  Widget _videoTile(MoodleLink l) => ListTile(
        dense: true,
        leading: Checkbox(value: study.isDone(l), onChanged: (_) => study.toggleDone(l)),
        title: Text(l.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text('${study.courses[l.cid] ?? ''} · ${(study.secondsOf(l) / 60).ceil()} د',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54)),
        trailing: IconButton(icon: const Icon(Icons.edit_note), tooltip: 'الدفتر', onPressed: () => _notebook(l)),
        onTap: () => _play(l),
      );

  // ---------------- plan ----------------
  Widget _planTab() {
    if (study.links.isEmpty) return _empty();
    final plan = study.plan();
    final left = study.videoLinks().where((l) => !study.isDone(l)).length;
    final totalMin = plan.fold<int>(0, (s, d) => s + d.minutes);
    final now = DateTime.now();
    final daysLeft = study.deadline.difference(DateTime(now.year, now.month, now.day)).inDays + 1;
    final perDay = plan.isEmpty ? 0 : (totalMin / (daysLeft < 1 ? 1 : daysLeft)).ceil();
    return ListView(padding: const EdgeInsets.all(12), children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.event_available, color: kAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Text('الموعد: ${study.deadline.day}/${study.deadline.month}/${study.deadline.year}'
                  '${daysLeft > 0 ? ' (باقي $daysLeft يوم)' : ' (انتهى)'}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            TextButton(onPressed: _pickDeadline, child: const Text('تغيير')),
          ]),
          const SizedBox(height: 6),
          Text(
              left == 0
                  ? 'أنهيت كل الفيديوهات 🎉'
                  : '$left فيديو متبقٍ · ${fmtMinutes(totalMin)} · حوالي ${fmtMinutes(perDay)} يومياً',
              style: const TextStyle(color: Colors.white70, height: 1.5)),
          if (study.fetching)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('جاري قراءة مدد الفيديوهات ${study.fetched}/${study.toFetch}...',
                  style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
            )
          else if (study.unknownDurations > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${study.unknownDurations} فيديو لم تُعرف مدته (حُسب كـ 15 دقيقة)',
                  style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < plan.length; i++)
        Card(
          color: kSurface,
          child: ExpansionTile(
            key: ValueKey('day$i${plan[i].items.length}'),
            initiallyExpanded: i == 0,
            leading: Icon(i == 0 ? Icons.today : Icons.calendar_month, color: i == 0 ? kAccent : null),
            title: Text(_dayLabel(plan[i]), style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${plan[i].items.length} فيديو · ${fmtMinutes(plan[i].minutes)}',
                style: const TextStyle(color: Colors.white54)),
            children: [
              if (i == 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => startPlaylistLock(context, plan[i].items),
                      icon: const Icon(Icons.lock),
                      label: const Text('ابدأ جلسة اليوم (قفل)'),
                    ),
                  ),
                ),
              for (final l in plan[i].items) _videoTile(l),
            ],
          ),
        ),
    ]);
  }

  // ---------------- progress ----------------
  Widget _progressTab() {
    if (study.links.isEmpty) return _empty();
    final all = study.totalAll, dn = study.doneAll;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('التقدم الكلي: ${all == 0 ? 0 : (dn * 100 / all).round()}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: all == 0 ? 0 : dn / all, color: kAccent, minHeight: 8),
          const SizedBox(height: 6),
          Text('$dn من $all منجز (فيديوهات وملفات)', style: const TextStyle(color: Colors.white54)),
        ]),
      ),
      const SizedBox(height: 12),
      for (final id in study.courseIds())
        if (study.totalOf(id) > 0)
          Card(
            color: kSurface,
            child: ExpansionTile(
              title: Text(study.courses[id] ?? 'مادة $id', maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  LinearProgressIndicator(value: study.doneOf(id) / study.totalOf(id), color: kAccent),
                  const SizedBox(height: 4),
                  Text('${study.doneOf(id)}/${study.totalOf(id)} · ${(study.doneOf(id) * 100 / study.totalOf(id)).round()}%',
                      style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
                ]),
              ),
              children: [
                for (final l in study.countableOf(id))
                  CheckboxListTile(
                    dense: true,
                    value: study.isDone(l),
                    onChanged: (_) => study.toggleDone(l),
                    secondary: Icon(groupIcon(l.group), color: l.group == 'yt' ? kAccent : null),
                    title: Text(l.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ),
    ]);
  }

  // ---------------- notebook ----------------
  Widget _notebookTab() {
    if (study.links.isEmpty) return _empty();
    final allQs = study.notes.values.expand((n) => n.qs).toList();
    return ListView(padding: const EdgeInsets.all(12), children: [
      FilledButton.icon(
        onPressed: allQs.isEmpty
            ? null
            : () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuizPage(questions: allQs))),
        icon: const Icon(Icons.quiz),
        label: Text('اختبار عام (${allQs.length} سؤال)'),
      ),
      const SizedBox(height: 10),
      for (final id in study.courseIds())
        if (study.totalOf(id) > 0)
          Card(
            color: kSurface,
            child: ExpansionTile(
              title: Text(study.courses[id] ?? 'مادة $id', maxLines: 2, overflow: TextOverflow.ellipsis),
              children: [
                for (final l in study.countableOf(id))
                  ListTile(
                    dense: true,
                    leading: Icon(groupIcon(l.group), color: l.group == 'yt' ? kAccent : null),
                    title: Text(l.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: (study.noteOf(l)?.isEmpty ?? true)
                        ? null
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.edit_note, color: kAccent),
                            Text('${study.noteOf(l)!.qs.length}'),
                          ]),
                    onTap: () => _notebook(l),
                  ),
              ],
            ),
          ),
    ]);
  }

  @override
  Widget build(BuildContext c) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Row(children: [Icon(Icons.event_note, color: kAccent), SizedBox(width: 10), Text('المرشد الدراسي')]),
            bottom: const TabBar(tabs: [Tab(text: 'الخطة'), Tab(text: 'التقدم'), Tab(text: 'الدفتر')]),
          ),
          body: AnimatedBuilder(
            animation: study,
            builder: (_, __) => TabBarView(children: [_planTab(), _progressTab(), _notebookTab()]),
          ),
        ),
      );
}
