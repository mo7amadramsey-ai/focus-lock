import 'links_page.dart';
import 'study.dart';

/// A smarter study plan. Unlike a plain even split it
///  - puts the courses that are closest to an exam / deadline, and the ones you answer worst, first,
///  - mixes 2-3 courses inside the same days (weights 3:2:1) instead of one long block per course,
///  - never schedules a lecture after the exam of its own course when there is room before it,
///  - tells WHY each day looks the way it does, and warns when the time really is not enough.
class SmartDay {
  final DateTime date;
  final List<MoodleLink> items = [];
  final List<AgendaItem> tasks = [];
  final Set<String> courses = {};
  int minutes = 0;
  String why = '';
  SmartDay(this.date);
}

class SmartPlan {
  final List<SmartDay> days; // only the days that have work
  final int needMin, capacityMin;
  final List<String> risks;
  const SmartPlan(this.days, this.needMin, this.capacityMin, this.risks);
  int get shortMin => needMin > capacityMin ? needMin - capacityMin : 0;
}

extension SmartPlanX on StudyStore {
  SmartPlan smartPlan() {
    final today = dayOnly(DateTime.now());
    final now = DateTime.now();
    var n = planEnd.difference(today).inDays + 1;
    if (n < 1) n = 1;
    final list = List.generate(n, (i) => SmartDay(DateTime(today.year, today.month, today.day + i)));
    final focus = focusCourses.isNotEmpty;
    final cap = dailyMinutes;

    // assignments / quizzes / exams: the work goes on the day before they are due
    final upcoming = agenda().where((a) => !a.done && !a.when.isBefore(now) && (!focus || a.cid.isEmpty || focusCourses.contains(a.cid))).toList();
    final nearest = <String, DateTime>{};
    final examIdx = <String, int>{}; // last day index on which the course's lectures can still be studied
    var taskMin = 0;
    for (final a in upcoming) {
      final di = dayOnly(a.when).difference(today).inDays;
      final idx = (di - 1).clamp(0, n - 1).toInt();
      final m = effortMin(a);
      list[idx].tasks.add(a);
      list[idx].minutes += m;
      taskMin += m;
      if (a.cid.isNotEmpty) {
        list[idx].courses.add(a.cid);
        final cur = nearest[a.cid];
        if (cur == null || a.when.isBefore(cur)) nearest[a.cid] = a.when;
        if (a.isExam) {
          final old = examIdx[a.cid];
          if (old == null || idx < old) examIdx[a.cid] = idx;
        }
      }
    }

    // lectures still to watch, per course
    final byC = <String, List<MoodleLink>>{};
    for (final l in videoLinks()) {
      if (isDone(l) || (focus && !focusCourses.contains(l.cid))) continue;
      byC.putIfAbsent(l.cid, () => []).add(l);
    }
    int mins(MoodleLink l) => (secondsOf(l) / 60).ceil();
    var videoMin = 0;
    final left = <String, int>{};
    byC.forEach((k, v) {
      final s = v.fold<int>(0, (a, l) => a + mins(l));
      left[k] = s;
      videoMin += s;
    });

    double score(String c) {
      final dn = nearest[c];
      final days = dn == null ? 365 : dayOnly(dn).difference(today).inDays.clamp(0, 365).toInt();
      final urgency = dn == null ? 0.0 : 1 / (1 + days);
      final u = understandingCourse(c);
      final weak = u == null ? 0.3 : 1 - u;
      final size = videoMin == 0 ? 0.0 : (left[c] ?? 0) / videoMin;
      return urgency * 3 + weak + size * .5;
    }

    final order = byC.keys.toList()..sort((a, b) => score(b).compareTo(score(a)));
    const weights = [3, 2, 1];
    final queue = <MoodleLink>[];
    while (true) {
      final active = order.where((c) => byC[c]!.isNotEmpty).take(3).toList();
      if (active.isEmpty) break;
      for (var w = 0; w < active.length; w++) {
        final q = byC[active[w]]!;
        for (var k = 0; k < weights[w] && q.isNotEmpty; k++) {
          queue.add(q.removeAt(0));
        }
      }
    }

    // place them: even load, but never after the exam of their own course if there is room before it
    final total = videoMin + taskMin;
    final target = (total / n).ceil();
    var d = 0;
    var forced = 0;
    for (final l in queue) {
      final m = mins(l);
      while (d < n - 1 && (list[d].minutes >= target || (list[d].items.isNotEmpty && list[d].minutes + m > target))) {
        d++;
      }
      var at = d;
      final lim = examIdx[l.cid] ?? (n - 1);
      if (at > lim) {
        var best = -1;
        for (var k = 0; k <= lim; k++) {
          if (list[k].minutes + m <= cap) {
            best = k;
            break;
          }
        }
        if (best < 0) {
          best = 0;
          for (var k = 1; k <= lim; k++) {
            if (list[k].minutes < list[best].minutes) best = k;
          }
          forced++;
        }
        at = best;
      }
      list[at].items.add(l);
      list[at].minutes += m;
      list[at].courses.add(l.cid);
    }

    // why each day looks like this
    for (var i = 0; i < n; i++) {
      final day = list[i];
      String? why;
      if (day.tasks.isNotEmpty) {
        final t = day.tasks.first;
        why = 'تجهيز لـ «${t.title}» (${t.isExam ? 'اختبار' : 'موعد'} ${t.when.day}/${t.when.month})';
      } else {
        for (final c in day.courses) {
          final e = examIdx[c];
          if (e == null) continue;
          final daysTo = e + 1 - i;
          if (daysTo >= 1 && daysTo <= 10) {
            why = 'قبل اختبار ${courses[c] ?? c} بـ $daysTo ${daysTo == 1 ? 'يوم' : 'أيام'}';
            break;
          }
        }
      }
      day.why = why ?? (day.items.isEmpty ? '' : 'تقدّم منتظم نحو الموعد');
    }

    final risks = <String>[];
    if (forced > 0) risks.add('وقتك قبل بعض الاختبارات لا يكفي مواد هذه الاختبارات: ابدأ اليوم أو زد ساعاتك اليومية.');
    final over = list.where((x) => x.minutes > cap).length;
    if (over > 0) risks.add('$over ${over == 1 ? 'يوم' : 'أيام'} أكثر من ساعاتك اليومية.');
    final late = overdue().length;
    if (late > 0) risks.add('عندك $late ${late == 1 ? 'عنصر متأخر' : 'عناصر متأخرة'} لم تُنجز.');

    return SmartPlan(list.where((x) => x.items.isNotEmpty || x.tasks.isNotEmpty).toList(), total, n * cap, risks);
  }
}
