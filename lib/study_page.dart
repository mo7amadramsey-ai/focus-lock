import 'package:flutter/material.dart';
import 'calendar_tab.dart';
import 'course_download.dart';
import 'follow_tab.dart';
import 'links_page.dart';
import 'lock_modes.dart';
import 'lock_setup.dart';
import 'moodle_page.dart';
import 'notebook_page.dart';
import 'notebook_tab.dart';
import 'preview_page.dart';
import 'settings_page.dart';
import 'stats_tab.dart';
import 'study.dart';
import 'theme.dart';

/// Private study mentor, all local on the phone: today, plan, calendar, follow-up, progress, notebook, statistics.
class StudyPage extends StatefulWidget {
  const StudyPage({super.key});
  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  @override
  void initState() {
    super.initState();
    study.load().then((_) {
      study.fetchDurations();
      if (study.remindersOn) study.askNotifications();
    });
  }

  @override
  Widget build(BuildContext c) => DefaultTabController(
        length: 7,
        child: Scaffold(
          appBar: AppBar(
            title: const Row(children: [Icon(Icons.event_note, color: kAccent), SizedBox(width: 10), Text('المرشد الدراسي')]),
            actions: [
              IconButton(
                tooltip: 'الإعدادات',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const StudySettingsPage())),
              ),
            ],
            bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
              Tab(text: 'اليوم'),
              Tab(text: 'الخطة'),
              Tab(text: 'التقويم'),
              Tab(text: 'المتابعة'),
              Tab(text: 'التقدم'),
              Tab(text: 'الدفتر'),
              Tab(text: 'الإحصاءات'),
            ]),
          ),
          body: AnimatedBuilder(
            animation: study,
            builder: (_, __) => TabBarView(children: [
              const TodayTab(),
              const PlanTab(),
              const CalendarTab(),
              const FollowTab(),
              const ProgressTab(),
              const NotebookTab(),
              const StatsTab(),
            ]),
          ),
        ),
      );
}

Widget emptyStudy(BuildContext context) => Center(
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

void playLink(BuildContext c, MoodleLink l) => Navigator.push(
    c, MaterialPageRoute(builder: (_) => PreviewPage(url: l.url, title: l.title, youtubeId: ytId(l))));

void openNotebook(BuildContext c, MoodleLink l) =>
    Navigator.push(c, MaterialPageRoute(builder: (_) => NotebookPage(link: l)));

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
      subtitle: Text('${study.courses[l.cid] ?? ''} · ${(study.secondsOf(l) / 60).ceil()} د',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54)),
      trailing: IconButton(icon: const Icon(Icons.edit_note), tooltip: 'الدفتر', onPressed: () => openNotebook(c, l)),
      onTap: () => playLink(c, l),
    );

Widget agendaTile(AgendaItem a) {
  final late = !a.done && a.when.isBefore(DateTime.now());
  final icon = a.isExam ? Icons.school : a.kind == 'quiz' ? Icons.quiz : Icons.assignment;
  return ListTile(
    dense: true,
    leading: Icon(icon, color: a.done ? Colors.greenAccent : late ? Colors.redAccent : kAccent),
    title: Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text('${dayLabel(a.when)} ${clock(a.when)}${late ? ' · متأخر' : ''}${a.cid.isNotEmpty ? ' · ${study.courses[a.cid] ?? ''}' : ''}',
        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: late ? Colors.redAccent : Colors.white54)),
    trailing: Checkbox(
      value: a.done,
      onChanged: (_) {
        if (a.manualId != null) {
          final e = study.manual.firstWhere((x) => x.id == a.manualId);
          study.toggleManualDone(e);
        } else {
          final t = study.tasks.firstWhere((x) => 'task|${x.url}' == a.key);
          study.toggleTaskDone(t);
        }
      },
    ),
  );
}

// ---------------- today ----------------
class TodayTab extends StatelessWidget {
  const TodayTab({super.key});
  @override
  Widget build(BuildContext c) {
    if (study.links.isEmpty && study.manual.isEmpty) return emptyStudy(c);
    final res = study.planFull();
    final todayPlan = res.days.where((d) => dayOnly(d.date) == dayOnly(DateTime.now())).toList();
    final now = DateTime.now();
    final soon = study.agenda().where((a) => !a.done && !a.when.isBefore(now) && a.when.isBefore(now.add(const Duration(days: 7)))).toList();
    final late = study.overdue();
    final due = study.dueQuestions().length;
    final all = study.totalAll;
    return ListView(padding: const EdgeInsets.all(12), children: [
      if (study.notice != null)
        Card(color: Colors.orange.withOpacity(0.2), child: Padding(padding: const EdgeInsets.all(12), child: Text(study.notice!))),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('تقدمك: ${all == 0 ? 0 : (study.doneAll * 100 / all).round()}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: all == 0 ? 0 : study.doneAll / all, color: kAccent, minHeight: 8),
          const SizedBox(height: 8),
          Text('${study.doneAll} من $all منجز · تتابع ${study.streak} يوم', style: const TextStyle(color: Colors.white60)),
        ]),
      ),
      const SizedBox(height: 10),
      if (todayPlan.isNotEmpty && todayPlan.first.items.isNotEmpty)
        Card(
          color: kSurface,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('خطة اليوم: ${todayPlan.first.items.length} فيديو · ${fmtMinutes(todayPlan.first.minutes)}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => startPlaylistLock(c, todayPlan.first.items),
                  icon: const Icon(Icons.lock),
                  label: const Text('ابدأ جلسة اليوم (قفل)'),
                ),
              ),
            ]),
          ),
        ),
      if (res.shortMin > 0)
        Card(
          color: Colors.red.withOpacity(0.18),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('تنبيه: المطلوب لا يتسع في ساعاتك. ينقصك ${fmtMinutes(res.shortMin)}. زد ساعات الدراسة اليومية أو أجّل الموعد من الإعدادات.',
                style: const TextStyle(height: 1.5)),
          ),
        ),
      if (due > 0)
        Card(
          color: kSurface,
          child: ListTile(
            leading: const Icon(Icons.replay_circle_filled, color: kAccent),
            title: Text('مراجعة اليوم: $due سؤال'),
            subtitle: const Text('مراجعة متباعدة من أسئلة دفاترك'),
            onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => QuizPage(refs: study.dueQuestions(), title: 'مراجعة اليوم'))),
          ),
        ),
      if (late.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.fromLTRB(4, 10, 4, 4), child: Text('متأخر', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w800))),
        for (final a in late.reversed.take(5)) agendaTile(a),
      ],
      const Padding(padding: EdgeInsets.fromLTRB(4, 10, 4, 4), child: Text('القادم خلال 7 أيام', style: TextStyle(fontWeight: FontWeight.w800))),
      if (soon.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('لا مواعيد قريبة', style: TextStyle(color: Colors.white54))),
      for (final a in soon) agendaTile(a),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const MoodlePage())),
        icon: const Icon(Icons.sync),
        label: const Text('مزامنة المودل'),
      ),
    ]);
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
    final left = study.videoLinks().where((l) => !study.isDone(l)).length;
    final daysLeft = study.deadline.difference(dayOnly(DateTime.now())).inDays + 1;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.event_available, color: kAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Text('الموعد: ${study.deadline.day}/${study.deadline.month}/${study.deadline.year}${daysLeft > 0 ? ' (باقي $daysLeft يوم)' : ' (انتهى)'}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            TextButton(onPressed: () => _pickDeadline(c), child: const Text('تغيير')),
          ]),
          const SizedBox(height: 6),
          Text(
              left == 0 && res.needMin == 0
                  ? 'أنهيت كل المطلوب 🎉'
                  : '$left فيديو متبقٍ · المطلوب ${fmtMinutes(res.needMin)} · متاحك ${fmtMinutes(res.capacityMin)} (${fmtMinutes(study.dailyMinutes)} يومياً)',
              style: const TextStyle(color: Colors.white70, height: 1.5)),
          if (res.shortMin > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('⚠ العجز ${fmtMinutes(res.shortMin)}: لا يمكن إنهاء كل شيء بهذه الساعات. زد الساعات اليومية أو أجّل الموعد، ولن أعرض خطة مستحيلة على أنها ممكنة.',
                  style: const TextStyle(color: Colors.redAccent, height: 1.5)),
            ),
          if (study.fetching)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('جاري قراءة مدد الفيديوهات ${study.fetched}/${study.toFetch}...', style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
            )
          else if (study.unknownDurations > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${study.unknownDurations} فيديو لم تُعرف مدته (حُسب كـ 15 دقيقة)', style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < plan.length; i++)
        Card(
          color: kSurface,
          child: ExpansionTile(
            key: ValueKey('day$i${plan[i].items.length}${plan[i].tasks.length}'),
            initiallyExpanded: i == 0,
            leading: Icon(i == 0 ? Icons.today : Icons.calendar_month, color: i == 0 ? kAccent : null),
            title: Text(dayLabel(plan[i].date), style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
                '${plan[i].items.length} فيديو${plan[i].tasks.isNotEmpty ? ' · ${plan[i].tasks.length} تسليم/اختبار' : ''} · ${fmtMinutes(plan[i].minutes)}'
                '${plan[i].minutes > study.dailyMinutes ? ' · أكثر من ساعاتك' : ''}',
                style: TextStyle(color: plan[i].minutes > study.dailyMinutes ? Colors.orangeAccent : Colors.white54)),
            children: [
              if (plan[i].items.isNotEmpty && dayOnly(plan[i].date) == dayOnly(DateTime.now()))
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => startPlaylistLock(c, plan[i].items),
                      icon: const Icon(Icons.lock),
                      label: const Text('ابدأ جلسة اليوم (قفل)'),
                    ),
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

// ---------------- progress ----------------
class ProgressTab extends StatelessWidget {
  const ProgressTab({super.key});
  @override
  Widget build(BuildContext c) {
    if (study.links.isEmpty) return emptyStudy(c);
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
        if (study.totalOf(id) > 0) _course(c, id),
    ]);
  }

  Widget _course(BuildContext c, String id) {
    final und = study.understandingCourse(id);
    final chapters = study.chaptersOf(id);
    return Card(
      color: kSurface,
      child: ExpansionTile(
        title: Text(study.courses[id] ?? 'مادة $id', maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LinearProgressIndicator(value: study.doneOf(id) / study.totalOf(id), color: kAccent),
            const SizedBox(height: 4),
            Text('${study.doneOf(id)}/${study.totalOf(id)} · ${(study.doneOf(id) * 100 / study.totalOf(id)).round()}%'
                '${und != null ? ' · الفهم ${(und * 100).round()}%' : ''}',
                style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
          ]),
        ),
        children: [
          for (final ch in chapters) ...[
            if (ch.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                child: Text(
                    '$ch · ${study.countableOf(id).where((l) => l.sec == ch && study.isDone(l)).length}/${study.countableOf(id).where((l) => l.sec == ch).length}',
                    style: const TextStyle(color: kAccent, fontWeight: FontWeight.w700)),
              ),
            for (final l in study.countableOf(id).where((l) => l.sec == ch))
              CheckboxListTile(
                dense: true,
                value: study.isDone(l),
                onChanged: (_) => study.toggleDone(l),
                secondary: Icon(groupIcon(l.group), color: l.group == 'yt' ? kAccent : null),
                title: Text(l.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: study.understandingOf(l) == null
                    ? null
                    : Text('الفهم ${(study.understandingOf(l)! * 100).round()}%', style: const TextStyle(fontSize: 12)),
              ),
          ],
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              onPressed: () => downloadCourseVideos(c, id),
              icon: const Icon(Icons.download),
              label: const Text('تنزيل فيديوهات المادة كاملة'),
            ),
          ),
        ],
      ),
    );
  }
}
