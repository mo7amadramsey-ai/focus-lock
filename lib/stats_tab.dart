import 'package:flutter/material.dart';
import 'study.dart';
import 'theme.dart';
import 'lock_setup.dart';

/// Study statistics: time counted by the strict sessions, streak, quiz accuracy, exams
class StatsTab extends StatelessWidget {
  const StatsTab({super.key});

  Widget _card(String t, String v, IconData i) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, color: kAccent),
          const SizedBox(height: 8),
          Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(t, style: TextStyle(color: kMuted, fontSize: 12.5)),
        ]),
      );

  @override
  Widget build(BuildContext c) {
    final today = dayOnly(DateTime.now());
    final week = [for (var i = 6; i >= 0; i--) DateTime(today.year, today.month, today.day - i)];
    final secs = [for (final d in week) study.secsOnDay(d)];
    final mx = secs.fold<int>(1, (m, s) => s > m ? s : m);
    final total = study.daySecs.values.fold<int>(0, (s, v) => s + v);
    final sessions = study.daySessions.values.fold<int>(0, (s, v) => s + v);
    var r = 0, w = 0;
    for (final q in study.allQuestions()) {
      r += q.qa.right;
      w += q.qa.wrong;
    }
    return ListView(padding: const EdgeInsets.all(12), children: [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.9,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        children: [
          _card('اليوم', fmtMinutes(study.secsOnDay(today) ~/ 60), Icons.today),
          _card('آخر 7 أيام', fmtMinutes(secs.fold<int>(0, (s, v) => s + v) ~/ 60), Icons.date_range),
          _card('أيام متتالية', '${study.streak}', Icons.local_fire_department),
          _card('الجلسات', '$sessions', Icons.lock_clock),
          _card('منجز', '${study.doneAll}/${study.totalAll}', Icons.check_circle_outline),
          _card('دقة الإجابات', r + w == 0 ? '—' : '${(r * 100 / (r + w)).round()}%', Icons.track_changes),
        ],
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('وقت الدراسة (آخر 7 أيام)', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          SizedBox(
            height: 110,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text(secs[i] == 0 ? '' : '${secs[i] ~/ 60}', style: TextStyle(fontSize: 11, color: kMuted)),
                    const SizedBox(height: 2),
                    Container(
                      height: 6 + 70.0 * secs[i] / mx,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(color: secs[i] == 0 ? kLine : kAccent, borderRadius: BorderRadius.circular(6)),
                    ),
                    const SizedBox(height: 4),
                    Text(dayName(week[i]).substring(0, 3), style: TextStyle(fontSize: 11, color: kMuted)),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          Text('إجمالي وقت الدراسة المحسوب: ${fmtMinutes(total ~/ 60)}', style: TextStyle(color: kMuted)),
          Text('يُحسب الوقت أثناء جلسات القفل فقط (والتشغيل الفعلي).', style: TextStyle(color: kFaint, fontSize: 12)),
        ]),
      ),
      if (study.examLog.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.fromLTRB(4, 16, 4, 6), child: Text('آخر الامتحانات', style: TextStyle(fontWeight: FontWeight.w800))),
        for (final e in study.examLog.take(8))
          ListTile(
            dense: true,
            leading: const Icon(Icons.school_outlined),
            title: Text('${e['score']} من ${e['total']}'),
            subtitle: Text('${study.courses['${e['cid']}'] ?? 'كل المواد'} · ${(DateTime.tryParse('${e['at']}') ?? today).day}/${(DateTime.tryParse('${e['at']}') ?? today).month}'),
          ),
      ],
      const Padding(padding: EdgeInsets.fromLTRB(4, 16, 4, 6), child: Text('الفهم لكل مادة (من نتائج الاختبارات)', style: TextStyle(fontWeight: FontWeight.w800))),
      for (final id in study.courseIds())
        if (study.totalOf(id) > 0)
          ListTile(
            dense: true,
            title: Text(study.courses[id] ?? 'مادة $id', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: LinearProgressIndicator(value: study.understandingCourse(id) ?? 0, color: kAccent),
            trailing: Text(study.understandingCourse(id) == null ? '—' : '${(study.understandingCourse(id)! * 100).round()}%'),
          ),
    ]);
  }
}
