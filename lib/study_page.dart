import 'package:flutter/material.dart';
import 'links_page.dart';
import 'lock_modes.dart';
import 'lock_setup.dart';
import 'moodle_page.dart';
import 'notebook_page.dart';
import 'preview_page.dart';
import 'study.dart';
import 'theme.dart';

// Shared pieces of the study screens (plan, calendar, home, courses)

Widget emptyStudy(BuildContext context) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.travel_explore, size: 56, color: kFaint),
          const SizedBox(height: 12),
          Text('لا توجد مواد بعد. سجّل الدخول إلى المودل مرة واحدة ليقرأ التطبيق موادك.',
              textAlign: TextAlign.center, style: TextStyle(color: kSoft, height: 1.6)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const MoodlePage(autoSync: true)));
              await study.load();
              study.fetchDurations();
            },
            icon: const Icon(Icons.sync),
            label: const Text('مزامنة المودل'),
          ),
        ]),
      ),
    );

void playLink(BuildContext c, MoodleLink l) =>
    Navigator.push(c, MaterialPageRoute(builder: (_) => PreviewPage(url: l.url, title: l.title, youtubeId: ytId(l))));

void openNotebook(BuildContext c, MoodleLink l) => Navigator.push(c, MaterialPageRoute(builder: (_) => NotebookPage(link: l)));

String dayLabel(DateTime date) {
  final diff = dayOnly(date).difference(dayOnly(DateTime.now())).inDays;
  if (diff == 0) return 'اليوم';
  if (diff == 1) return 'غداً';
  if (diff == -1) return 'أمس';
  return '${dayName(date)} ${date.day}/${date.month}';
}

String clock(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

Widget videoTile(BuildContext c, MoodleLink l) => ListTile(
      dense: true,
      leading: Checkbox(value: study.isDone(l), onChanged: (_) => study.toggleDone(l)),
      title: Text(l.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('${study.courses[l.cid] ?? ''} · ${(study.secondsOf(l) / 60).ceil()} د', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: kMuted)),
      trailing: IconButton(icon: const Icon(Icons.edit_note), tooltip: 'الدفتر', onPressed: () => openNotebook(c, l)),
      onTap: () => playLink(c, l),
    );

Widget agendaTile(AgendaItem a) {
  final late = !a.done && a.when.isBefore(DateTime.now());
  final icon = a.isExam ? Icons.school : a.kind == 'quiz' ? Icons.quiz : Icons.assignment;
  return ListTile(
    dense: true,
    leading: Icon(icon, color: a.done ? kOk : late ? kAccent : kWarn),
    title: Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text('${dayLabel(a.when)} ${clock(a.when)}${late ? ' · متأخر' : ''}${a.cid.isNotEmpty ? ' · ${study.courses[a.cid] ?? ''}' : ''}',
        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: late ? kAccent : kMuted)),
    trailing: Checkbox(
      value: a.done,
      onChanged: (_) {
        if (a.manualId != null) {
          study.toggleManualDone(study.manual.firstWhere((x) => x.id == a.manualId));
        } else {
          study.toggleTaskDone(study.tasks.firstWhere((x) => 'task|${x.url}' == a.key));
        }
      },
    ),
  );
}

/// Focus on a few courses and finish them in a chosen time (e.g. 8 courses in 10 days)
Future<void> showFocusSheet(BuildContext c) async {
  final ids = study.courseIds().where((id) => study.videoLinks().any((l) => l.cid == id)).toList();
  if (ids.isEmpty) {
    ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('زامن المودل أولاً لتظهر موادك')));
    return;
  }
  final chosen = <String>{...study.focusCourses};
  var days = study.focusUntil == null ? 7 : study.focusUntil!.difference(dayOnly(DateTime.now())).inDays.clamp(1, 365);
  final ok = await showModalBottomSheet<bool>(
    context: c,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .85,
        maxChildSize: .95,
        builder: (_, sc) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('ركّز على مواد محددة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('اختر المواد ثم المدة، وتُنشأ خطة لها وحدها.', style: TextStyle(color: kMuted)),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(controller: sc, children: [
                for (final id in ids)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: chosen.contains(id),
                    onChanged: (v) => set(() => v == true ? chosen.add(id) : chosen.remove(id)),
                    title: Text(study.courses[id] ?? id, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${study.videoLinks().where((l) => l.cid == id && !study.isDone(l)).length} فيديو متبقٍ', style: TextStyle(color: kMuted)),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            Text('المدة: ${days == 1 ? 'يوم' : '$days يوماً'}', style: const TextStyle(fontWeight: FontWeight.w800)),
            Wrap(spacing: 8, children: [
              for (final d in [2, 3, 5, 7, 10, 14, 21, 30])
                ChoiceChip(label: Text('$d'), selected: days == d, onSelected: (_) => set(() => days = d)),
            ]),
            Slider(min: 1, max: 60, divisions: 59, value: days.clamp(1, 60).toDouble(), onChanged: (v) => set(() => days = v.round())),
            Row(children: [
              if (study.focusCourses.isNotEmpty)
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء التركيز'))),
              if (study.focusCourses.isNotEmpty) const SizedBox(width: 10),
              Expanded(flex: 2, child: FilledButton(onPressed: chosen.isEmpty ? null : () => Navigator.pop(ctx, true), child: const Text('أنشئ الخطة'))),
            ]),
          ]),
        ),
      ),
    ),
  );
  if (ok == true) {
    study.setFocus(chosen, dayOnly(DateTime.now()).add(Duration(days: days - 1)));
  } else if (ok == false) {
    study.clearFocus();
  }
}

// ---------------- plan ----------------
class PlanTab extends StatelessWidget {
  const PlanTab({super.key});

  Future<void> _pickDeadline(BuildContext c) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: c,
      initialDate: study.deadline.isBefore(now) ? now : study.deadline,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
      helpText: 'موعد إنهاء كل المواد',
    );
    if (d != null) study.setDeadline(d);
  }

  @override
  Widget build(BuildContext c) {
    if (study.links.isEmpty && study.manual.isEmpty) return emptyStudy(c);
    final res = study.planFull();
    final plan = res.days;
    final focus = study.focusCourses.isNotEmpty;
    final left = study.videoLinks().where((l) => !study.isDone(l) && (!focus || study.focusCourses.contains(l.cid))).length;
    final end = study.planEnd;
    final daysLeft = end.difference(dayOnly(DateTime.now())).inDays + 1;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(focus ? Icons.center_focus_strong : Icons.event_available, color: kAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    focus
                        ? 'تركيز على ${study.focusCourses.length} مواد حتى ${end.day}/${end.month}'
                        : 'الموعد: ${end.day}/${end.month}/${end.year}${daysLeft > 0 ? ' (باقي $daysLeft يوم)' : ' (انتهى)'}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              if (!focus) TextButton(onPressed: () => _pickDeadline(c), child: const Text('تغيير')),
            ]),
            const SizedBox(height: 6),
            Text(
                left == 0 && res.needMin == 0
                    ? 'أنهيت كل المطلوب 🎉'
                    : '$left فيديو متبقٍ · المطلوب ${fmtMinutes(res.needMin)} · متاحك ${fmtMinutes(res.capacityMin)} (${fmtMinutes(study.dailyMinutes)} يومياً)',
                style: TextStyle(color: kSoft, height: 1.5)),
            if (res.shortMin > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('⚠ العجز ${fmtMinutes(res.shortMin)}: لا يتسع كل المطلوب في هذه الساعات. زد ساعاتك اليومية أو أطل المدة، ولن أعرض خطة مستحيلة على أنها ممكنة.',
                    style: TextStyle(color: kAccent, height: 1.5)),
              ),
            if (study.fetching)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text('جاري قراءة مدد الفيديوهات ${study.fetched}/${study.toFetch}...', style: TextStyle(color: kMuted, fontSize: 12.5)))
            else if (study.unknownDurations > 0)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text('${study.unknownDurations} فيديو لم تُعرف مدته (حُسب كـ 15 دقيقة)', style: TextStyle(color: kMuted, fontSize: 12.5))),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              FilledButton.tonalIcon(onPressed: () => showFocusSheet(c), icon: const Icon(Icons.center_focus_strong, size: 18), label: Text(focus ? 'تعديل التركيز' : 'ركّز على مواد')),
              if (focus) OutlinedButton(onPressed: study.clearFocus, child: const Text('إلغاء التركيز')),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 6),
      for (var i = 0; i < plan.length; i++)
        Card(
          child: ExpansionTile(
            key: ValueKey('day$i${plan[i].items.length}${plan[i].tasks.length}'),
            initiallyExpanded: i == 0,
            shape: const Border(),
            collapsedShape: const Border(),
            leading: Icon(i == 0 ? Icons.today : Icons.calendar_month, color: i == 0 ? kAccent : null),
            title: Text(dayLabel(plan[i].date), style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
                '${plan[i].items.length} فيديو${plan[i].tasks.isNotEmpty ? ' · ${plan[i].tasks.length} تسليم/اختبار' : ''} · ${fmtMinutes(plan[i].minutes)}'
                '${plan[i].minutes > study.dailyMinutes ? ' · أكثر من ساعاتك' : ''}',
                style: TextStyle(color: plan[i].minutes > study.dailyMinutes ? kWarn : kMuted)),
            children: [
              if (plan[i].items.isNotEmpty && dayOnly(plan[i].date) == dayOnly(DateTime.now()))
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(onPressed: () => startPlaylistLock(c, plan[i].items), icon: const Icon(Icons.lock), label: const Text('ابدأ جلسة اليوم (قفل)')),
                  ),
                ),
              for (final a in plan[i].tasks) agendaTile(a),
              for (final l in plan[i].items) videoTile(c, l),
            ],
          ),
        ),
    ]);
  }
}
