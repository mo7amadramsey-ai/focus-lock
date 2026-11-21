import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'channel.dart';
import 'links_page.dart';

/// A review question of a lecture. type: qa (open) / tf (true-false) / mcq (multiple choice).
/// box + due give the spaced review (1 / 3 / 7 / 14 / 30 days); right / wrong feed the understanding indicator.
class QA {
  String q, a, type;
  List<String> opts;
  int ci, box, right, wrong;
  DateTime? due;
  QA(this.q, this.a,
      {this.type = 'qa', List<String>? opts, this.ci = 0, this.box = 0, this.right = 0, this.wrong = 0, this.due})
      : opts = opts ?? <String>[];
  Map<String, dynamic> toJson() => {
        'q': q, 'a': a, 't': type, 'o': opts, 'ci': ci, 'b': box, 'r': right, 'w': wrong,
        'd': due?.toIso8601String(),
      };
  factory QA.fromJson(Map j) => QA('${j['q']}', '${j['a']}',
      type: '${j['t'] ?? 'qa'}',
      opts: ((j['o'] as List?) ?? []).map((e) => '$e').toList(),
      ci: (j['ci'] as num?)?.toInt() ?? 0,
      box: (j['b'] as num?)?.toInt() ?? 0,
      right: (j['r'] as num?)?.toInt() ?? 0,
      wrong: (j['w'] as num?)?.toInt() ?? 0,
      due: DateTime.tryParse('${j['d']}'));
}

/// A note tied to a second of the video. src: me / lecturer (copied from the video's own captions)
class Stamp {
  int s;
  String text, src;
  Stamp(this.s, this.text, [this.src = 'me']);
  Map<String, dynamic> toJson() => {'s': s, 't': text, 'x': src};
  factory Stamp.fromJson(Map j) => Stamp((j['s'] as num).toInt(), '${j['t']}', '${j['x'] ?? 'me'}');
}

/// The notebook of one lecture
class Note {
  String text;
  final List<QA> qs;
  final List<Stamp> stamps;
  Note({this.text = '', List<QA>? qs, List<Stamp>? stamps})
      : qs = qs ?? <QA>[],
        stamps = stamps ?? <Stamp>[];
  bool get isEmpty => text.trim().isEmpty && qs.isEmpty && stamps.isEmpty;
  Map<String, dynamic> toJson() =>
      {'n': text, 'q': qs.map((e) => e.toJson()).toList(), 'st': stamps.map((e) => e.toJson()).toList()};
  factory Note.fromJson(Map j) => Note(
      text: '${j['n'] ?? ''}',
      qs: ((j['q'] as List?) ?? []).map((e) => QA.fromJson(e as Map)).toList(),
      stamps: ((j['st'] as List?) ?? []).map((e) => Stamp.fromJson(e as Map)).toList());
}

/// An assignment / quiz read from Moodle (kind: assign / quiz / exam)
class MoodleTask {
  final String cid, kind, title, url, rawDue;
  final DateTime? due;
  final bool? submitted; // null = unknown
  const MoodleTask(this.cid, this.kind, this.title, this.url, this.rawDue, this.due, this.submitted);
  Map<String, dynamic> toJson() =>
      {'c': cid, 'k': kind, 't': title, 'u': url, 'r': rawDue, 'd': due?.toIso8601String(), 's': submitted};
  factory MoodleTask.fromJson(Map j) => MoodleTask('${j['c']}', '${j['k']}', '${j['t']}', '${j['u']}', '${j['r'] ?? ''}',
      DateTime.tryParse('${j['d']}'), j['s'] as bool?);
}

/// An exam / task the student added by hand (Moodle does not always list exams)
class ManualEvent {
  final String id;
  String title, kind; // exam / task
  DateTime date;
  ManualEvent(this.id, this.title, this.kind, this.date);
  Map<String, dynamic> toJson() => {'i': id, 't': title, 'k': kind, 'd': date.toIso8601String()};
  factory ManualEvent.fromJson(Map j) =>
      ManualEvent('${j['i']}', '${j['t']}', '${j['k']}', DateTime.tryParse('${j['d']}') ?? DateTime.now());
}

/// A new item found by a Moodle sync
class FeedItem {
  final DateTime at;
  final String cid, kind, title, url;
  const FeedItem(this.at, this.cid, this.kind, this.title, this.url);
  Map<String, dynamic> toJson() => {'a': at.toIso8601String(), 'c': cid, 'k': kind, 't': title, 'u': url};
  factory FeedItem.fromJson(Map j) =>
      FeedItem(DateTime.tryParse('${j['a']}') ?? DateTime.now(), '${j['c']}', '${j['k']}', '${j['t']}', '${j['u']}');
}

/// Something with a date: Moodle task or manual event
class AgendaItem {
  final String title, kind, cid, key;
  final DateTime when;
  final bool done;
  final String? url;
  final String? manualId;
  const AgendaItem(this.title, this.kind, this.cid, this.when, this.done, this.key, {this.url, this.manualId});
  bool get isExam => kind == 'exam';
}

/// One day of the study plan
class PlanDay {
  final DateTime date;
  final List<MoodleLink> items = [];
  final List<AgendaItem> tasks = [];
  int minutes = 0;
  PlanDay(this.date);
}

class PlanResult {
  final List<PlanDay> days;
  final int needMin, capacityMin;
  const PlanResult(this.days, this.needMin, this.capacityMin);
  int get shortMin => needMin > capacityMin ? needMin - capacityMin : 0;
}

/// A question together with its lecture
class QRef {
  final String key;
  final QA qa;
  final MoodleLink? link;
  const QRef(this.key, this.qa, this.link);
}

/// YouTube id of a link (null for files / playlists / external links)
String? ytId(MoodleLink l) => l.group == 'yt' ? VideoId.parseVideoId(l.url) : null;

/// What counts for progress (documents are tracked but are NOT part of the video plan)
bool countable(MoodleLink l) => const ['yt', 'video', 'pdf', 'doc'].contains(l.group);

/// Key used for "done" marks and notebooks (the same YouTube video shares them between courses)
String linkKey(MoodleLink l) => ytId(l) ?? '${l.cid}|${l.url}';

bool isExamTitle(String t) => RegExp(r'exam|midterm|final|امتحان|نصفي|نهائي|اختبار', caseSensitive: false).hasMatch(t);

const _days = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
String dayName(DateTime d) => _days[d.weekday - 1];
String dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
String fmtClock(int sec) {
  final h = sec ~/ 3600, m = (sec % 3600) ~/ 60, s = sec % 60;
  return h > 0
      ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
      : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

// ---------- reading Moodle dates (English or Arabic month names, Arabic-Indic digits) ----------
const _months = <String, int>{
  'january': 1, 'february': 2, 'march': 3, 'april': 4, 'may': 5, 'june': 6, 'july': 7, 'august': 8,
  'september': 9, 'october': 10, 'november': 11, 'december': 12,
  'كانون الثاني': 1, 'يناير': 1, 'شباط': 2, 'فبراير': 2, 'آذار': 3, 'اذار': 3, 'مارس': 3, 'نيسان': 4, 'أبريل': 4,
  'ابريل': 4, 'أيار': 5, 'ايار': 5, 'مايو': 5, 'حزيران': 6, 'يونيو': 6, 'تموز': 7, 'يوليو': 7, 'آب': 8, 'اب': 8,
  'أغسطس': 8, 'اغسطس': 8, 'أيلول': 9, 'ايلول': 9, 'سبتمبر': 9, 'تشرين الأول': 10, 'تشرين الاول': 10,
  'أكتوبر': 10, 'اكتوبر': 10, 'تشرين الثاني': 11, 'نوفمبر': 11, 'كانون الأول': 12, 'كانون الاول': 12, 'ديسمبر': 12,
};

String _latinDigits(String s) {
  final b = StringBuffer();
  for (final u in s.runes) {
    if (u >= 0x0660 && u <= 0x0669) {
      b.writeCharCode(u - 0x0660 + 48);
    } else if (u >= 0x06F0 && u <= 0x06F9) {
      b.writeCharCode(u - 0x06F0 + 48);
    } else {
      b.writeCharCode(u);
    }
  }
  return b.toString();
}

/// First date (and time, if any) written in [raw], or null
DateTime? parseMoodleDate(String raw) {
  final s = _latinDigits(raw).toLowerCase();
  int? d, mo, y;
  var end = 0;
  final names = _months.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  var best = -1;
  for (final n in names) {
    final m = RegExp('(\\d{1,2})\\s*$n[\\s,،]*(\\d{4})').firstMatch(s);
    if (m != null && (best < 0 || m.start < best)) {
      best = m.start;
      d = int.parse(m.group(1)!);
      mo = _months[n];
      y = int.parse(m.group(2)!);
      end = m.end;
    }
  }
  if (d == null) {
    final m = RegExp(r'(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})').firstMatch(s);
    if (m == null) return null;
    d = int.parse(m.group(1)!);
    mo = int.parse(m.group(2)!);
    y = int.parse(m.group(3)!);
    end = m.end;
  }
  if (mo == null || y == null || mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  var h = 23, mi = 59; // no time written: the end of that day
  final t = RegExp(r'(\d{1,2}):(\d{2})\s*(am|pm|ص|م)?').firstMatch(s.substring(end));
  if (t != null) {
    h = int.parse(t.group(1)!);
    mi = int.parse(t.group(2)!);
    final ap = t.group(3);
    if ((ap == 'pm' || ap == 'م') && h < 12) h += 12;
    if ((ap == 'am' || ap == 'ص') && h == 12) h = 0;
  }
  return DateTime(y, mo, d, h, mi);
}

/// Everything local on the phone: Moodle links, tasks, plan data, done marks, notebooks, reviews, study time.
/// No server and no AI: the plan, the review schedule and the statistics are plain arithmetic.
class StudyStore extends ChangeNotifier {
  final courses = <String, String>{};
  final links = <MoodleLink>[];
  final tasks = <MoodleTask>[];
  final manual = <ManualEvent>[];
  final feed = <FeedItem>[];
  final done = <String>{};
  final dur = <String, int>{}; // youtube id -> seconds
  final notes = <String, Note>{};
  final daySecs = <String, int>{}; // yyyy-MM-dd -> study seconds (counted by the strict sessions)
  final daySessions = <String, int>{};
  final examLog = <Map<String, dynamic>>[]; // {at, cid, score, total}
  DateTime deadline = DateTime(2026, 12, 2);
  int dailyMinutes = 180;
  bool remindersOn = true;
  String moodleHost = 'moodle.ucas.edu.ps';
  bool loaded = false, fetching = false;
  int fetched = 0, toFetch = 0;
  String? notice; // shown when a damaged file was restored from the backup copy
  Timer? _timer, _remTimer;
  int _pendingMs = 0;

  Future<String> _dir() async => (await getApplicationDocumentsDirectory()).path;

  Future<void> load() async {
    final d = await _dir();
    try {
      final f = File('$d/moodle_links.json');
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map;
        courses
          ..clear()
          ..addAll({for (final e in (j['courses'] as Map).entries) '${e.key}': '${e.value}'});
        links
          ..clear()
          ..addAll((j['links'] as List).map((e) => MoodleLink.fromJson(e as Map)));
      }
    } catch (_) {}
    if (!loaded) {
      Map? j;
      for (final name in ['study_state.json', 'study_state.json.bak']) {
        try {
          final f = File('$d/$name');
          if (await f.exists()) {
            j = jsonDecode(await f.readAsString()) as Map;
            if (name.endsWith('.bak')) notice = 'تعذّر قراءة ملف الدراسة، فاستُعيدت النسخة السابقة.';
            break;
          }
        } catch (_) {}
      }
      if (j != null) _apply(j);
      loaded = true;
    }
    notifyListeners();
  }

  void _apply(Map j) {
    done
      ..clear()
      ..addAll(((j['done'] as List?) ?? []).map((e) => '$e'));
    dur
      ..clear()
      ..addAll({for (final e in ((j['dur'] as Map?) ?? {}).entries) '${e.key}': (e.value as num).toInt()});
    notes
      ..clear()
      ..addAll({for (final e in ((j['notes'] as Map?) ?? {}).entries) '${e.key}': Note.fromJson(e.value as Map)});
    tasks
      ..clear()
      ..addAll(((j['tasks'] as List?) ?? []).map((e) => MoodleTask.fromJson(e as Map)));
    manual
      ..clear()
      ..addAll(((j['manual'] as List?) ?? []).map((e) => ManualEvent.fromJson(e as Map)));
    feed
      ..clear()
      ..addAll(((j['feed'] as List?) ?? []).map((e) => FeedItem.fromJson(e as Map)));
    daySecs
      ..clear()
      ..addAll({for (final e in ((j['secs'] as Map?) ?? {}).entries) '${e.key}': (e.value as num).toInt()});
    daySessions
      ..clear()
      ..addAll({for (final e in ((j['sess'] as Map?) ?? {}).entries) '${e.key}': (e.value as num).toInt()});
    examLog
      ..clear()
      ..addAll(((j['exams'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
    final dl = DateTime.tryParse('${j['deadline']}');
    if (dl != null) deadline = dl;
    dailyMinutes = (j['daily'] as num?)?.toInt() ?? dailyMinutes;
    remindersOn = j['rem'] as bool? ?? remindersOn;
    moodleHost = '${j['host'] ?? moodleHost}';
  }

  Map<String, dynamic> _state() => {
        'deadline': deadline.toIso8601String(),
        'daily': dailyMinutes,
        'rem': remindersOn,
        'host': moodleHost,
        'done': done.toList(),
        'dur': dur,
        'notes': {for (final e in notes.entries) if (!e.value.isEmpty) e.key: e.value.toJson()},
        'tasks': tasks.map((e) => e.toJson()).toList(),
        'manual': manual.map((e) => e.toJson()).toList(),
        'feed': feed.take(300).map((e) => e.toJson()).toList(),
        'secs': daySecs,
        'sess': daySessions,
        'exams': examLog,
      };

  void saveSoon() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), _write);
  }

  /// Atomic: write a temp file, keep the old one as .bak, then rename
  Future<void> _write() async {
    try {
      final d = await _dir();
      final tmp = File('$d/study_state.json.tmp');
      await tmp.writeAsString(jsonEncode(_state()), flush: true);
      final cur = File('$d/study_state.json');
      if (await cur.exists()) await cur.copy('$d/study_state.json.bak');
      await tmp.rename(cur.path);
    } catch (_) {}
  }

  // ---------------- done marks ----------------
  bool isDone(MoodleLink l) => done.contains(linkKey(l));

  void setDone(MoodleLink l, bool v) {
    v ? done.add(linkKey(l)) : done.remove(linkKey(l));
    saveSoon();
    notifyListeners();
    scheduleReminders();
  }

  void toggleDone(MoodleLink l) => setDone(l, !isDone(l));

  void setDeadline(DateTime d) {
    deadline = d;
    saveSoon();
    notifyListeners();
    scheduleReminders();
  }

  void setSettings({int? daily, bool? reminders, String? host}) {
    if (daily != null) dailyMinutes = daily;
    if (reminders != null) remindersOn = reminders;
    if (host != null && host.trim().isNotEmpty) moodleHost = host.trim().toLowerCase();
    saveSoon();
    notifyListeners();
    scheduleReminders();
  }

  // ---------------- progress ----------------
  List<MoodleLink> countableOf(String cid) => links.where((l) => l.cid == cid && countable(l)).toList();
  int totalOf(String cid) => countableOf(cid).length;
  int doneOf(String cid) => countableOf(cid).where(isDone).length;
  int get totalAll => links.where(countable).length;
  int get doneAll => links.where((l) => countable(l) && isDone(l)).length;

  List<String> courseIds() {
    final have = links.map((l) => l.cid).toSet();
    return [...courses.keys.where(have.contains), ...have.where((k) => !courses.containsKey(k))];
  }

  /// Chapters (Moodle sections) of a course, in Moodle order; '' = items without a section
  List<String> chaptersOf(String cid) {
    final out = <String>[];
    for (final l in links.where((l) => l.cid == cid && countable(l))) {
      if (!out.contains(l.sec)) out.add(l.sec);
    }
    return out;
  }

  // ---------------- notes ----------------
  Note? noteOf(MoodleLink l) => notes[linkKey(l)];
  Note ensureNote(MoodleLink l) => notes.putIfAbsent(linkKey(l), () => Note());
  MoodleLink? linkOfKey(String k) {
    for (final l in links) {
      if (linkKey(l) == k) return l;
    }
    return null;
  }

  // ---------------- review (spaced repetition) ----------------
  List<QRef> allQuestions({String? cid}) {
    final out = <QRef>[];
    for (final e in notes.entries) {
      final l = linkOfKey(e.key);
      if (cid != null && l?.cid != cid) continue;
      for (final q in e.value.qs) {
        out.add(QRef(e.key, q, l));
      }
    }
    return out;
  }

  List<QRef> dueQuestions() {
    final now = DateTime.now();
    return allQuestions().where((r) => r.qa.due == null || !r.qa.due!.isAfter(now)).toList();
  }

  List<QRef> mistakes() => allQuestions().where((r) => r.qa.wrong > 0 && r.qa.box == 0).toList();

  /// Right: next box (1 / 3 / 7 / 14 / 30 days). Wrong: back to box 0, tomorrow.
  void grade(QA q, bool ok) {
    const iv = [1, 3, 7, 14, 30];
    if (ok) {
      q.right++;
      q.box = min(q.box + 1, 4);
    } else {
      q.wrong++;
      q.box = 0;
    }
    q.due = dayOnly(DateTime.now()).add(Duration(days: iv[q.box]));
    saveSoon();
    notifyListeners();
  }

  /// Understanding comes from quiz results, not from watching: right answers / all answers (null = no answers yet)
  double? understandingOf(MoodleLink l) {
    final n = noteOf(l);
    if (n == null) return null;
    var r = 0, w = 0;
    for (final q in n.qs) {
      r += q.right;
      w += q.wrong;
    }
    return r + w == 0 ? null : r / (r + w);
  }

  double? understandingCourse(String cid) {
    var r = 0, w = 0;
    for (final x in allQuestions(cid: cid)) {
      r += x.qa.right;
      w += x.qa.wrong;
    }
    return r + w == 0 ? null : r / (r + w);
  }

  void logExam(String? cid, int score, int total) {
    examLog.insert(0, {'at': DateTime.now().toIso8601String(), 'cid': cid ?? '', 'score': score, 'total': total});
    saveSoon();
    notifyListeners();
  }

  // ---------------- agenda: Moodle tasks + manual events ----------------
  bool taskDone(MoodleTask t) => t.submitted == true || done.contains('task|${t.url}');

  void toggleTaskDone(MoodleTask t) {
    final k = 'task|${t.url}';
    done.contains(k) ? done.remove(k) : done.add(k);
    saveSoon();
    notifyListeners();
    scheduleReminders();
  }

  void toggleManualDone(ManualEvent e) {
    final k = 'm|${e.id}';
    done.contains(k) ? done.remove(k) : done.add(k);
    saveSoon();
    notifyListeners();
    scheduleReminders();
  }

  void addManual(String title, String kind, DateTime date) {
    manual.add(ManualEvent('${DateTime.now().microsecondsSinceEpoch}', title, kind, date));
    saveSoon();
    notifyListeners();
    scheduleReminders();
  }

  void removeManual(String id) {
    manual.removeWhere((e) => e.id == id);
    saveSoon();
    notifyListeners();
    scheduleReminders();
  }

  /// Every dated thing, sorted by date
  List<AgendaItem> agenda() {
    final out = <AgendaItem>[];
    for (final t in tasks) {
      if (t.due == null) continue;
      final kind = t.kind == 'quiz' && isExamTitle(t.title) ? 'exam' : t.kind;
      out.add(AgendaItem(t.title, kind, t.cid, t.due!, taskDone(t), 'task|${t.url}', url: t.url));
    }
    for (final e in manual) {
      out.add(AgendaItem(e.title, e.kind, '', e.date, done.contains('m|${e.id}'), 'm|${e.id}', manualId: e.id));
    }
    out.sort((a, b) => a.when.compareTo(b.when));
    return out;
  }

  int effortMin(AgendaItem a) => switch (a.kind) { 'exam' => 90, 'quiz' => 40, _ => 60 };

  // ---------------- Moodle sync results ----------------
  void recordCrawl(List<MoodleLink> fresh, List<MoodleTask> newTasks, {required bool first}) {
    final now = DateTime.now();
    if (!first) {
      for (final l in fresh) {
        feed.insert(0, FeedItem(now, l.cid, l.group, l.title, l.url));
      }
    }
    tasks
      ..clear()
      ..addAll(newTasks);
    saveSoon();
    notifyListeners();
    scheduleReminders();
    if (!first && fresh.isNotEmpty && remindersOn) {
      ch.invokeMethod('notifyNow', {
        'title': 'جديد في المودل',
        'body': '${fresh.length} عنصر جديد في موادك',
      }).catchError((_) {});
    }
  }

  // ---------------- video plan ----------------
  List<MoodleLink> videoLinks() {
    final byC = <String, List<MoodleLink>>{};
    for (final l in links) {
      if (ytId(l) != null) byC.putIfAbsent(l.cid, () => []).add(l);
    }
    final seen = <String>{};
    final out = <MoodleLink>[];
    final order = [...courses.keys.where(byC.containsKey), ...byC.keys.where((k) => !courses.containsKey(k))];
    for (final k in order) {
      for (final l in byC[k]!) {
        if (seen.add(ytId(l)!)) out.add(l);
      }
    }
    return out;
  }

  int secondsOf(MoodleLink l) => dur[ytId(l)] ?? 900; // unknown length: assume 15 minutes
  int get unknownDurations => videoLinks().where((l) => !isDone(l) && !dur.containsKey(ytId(l))).length;

  /// Plan from today to the deadline: videos + assignments / quizzes / exams (work is put on the day before each
  /// due date). Everything is recomputed from what is still not done, so a missed day is spread over the next days.
  /// If the work does not fit in the daily hours the result says how many minutes are missing (no impossible plan).
  PlanResult planFull() {
    final today = dayOnly(DateTime.now());
    var days = deadline.difference(today).inDays + 1;
    if (days < 1) days = 1;
    final list = List.generate(days, (i) => PlanDay(DateTime(today.year, today.month, today.day + i)));
    var taskMin = 0;
    for (final a in agenda()) {
      if (a.done || a.when.isBefore(DateTime.now())) continue;
      final idx = (dayOnly(a.when).difference(today).inDays - 1).clamp(0, days - 1);
      final m = effortMin(a);
      list[idx].tasks.add(a);
      list[idx].minutes += m;
      taskMin += m;
    }
    final todo = videoLinks().where((l) => !isDone(l)).toList();
    int mins(MoodleLink l) => (secondsOf(l) / 60).ceil();
    final videoMin = todo.fold<int>(0, (s, l) => s + mins(l));
    final target = ((videoMin + taskMin) / days).ceil();
    var d = 0;
    for (final l in todo) {
      final m = mins(l);
      while (d < days - 1 && (list[d].minutes >= target || (list[d].items.isNotEmpty && list[d].minutes + m > target))) {
        d++;
      }
      list[d].items.add(l);
      list[d].minutes += m;
    }
    final out = list.where((x) => x.items.isNotEmpty || x.tasks.isNotEmpty).toList();
    return PlanResult(out, videoMin + taskMin, days * dailyMinutes);
  }

  List<PlanDay> plan() => planFull().days;

  /// Overdue items that are not done
  List<AgendaItem> overdue() => agenda().where((a) => !a.done && a.when.isBefore(DateTime.now())).toList();

  Future<void> fetchDurations() async {
    if (fetching) return;
    final ids = <String>{};
    for (final l in links) {
      final id = ytId(l);
      if (id != null && !dur.containsKey(id)) ids.add(id);
    }
    final list = ids.toList();
    if (list.isEmpty) return;
    fetching = true;
    fetched = 0;
    toFetch = list.length;
    notifyListeners();
    final yt = YoutubeExplode();
    var next = 0;
    Future<void> worker() async {
      while (next < list.length) {
        final id = list[next++];
        try {
          final v = await yt.videos.get(id);
          final d = v.duration;
          if (d != null) dur[id] = d.inSeconds;
        } catch (_) {}
        fetched++;
        if (fetched % 5 == 0) notifyListeners();
      }
    }

    await Future.wait([worker(), worker(), worker(), worker()]);
    yt.close();
    fetching = false;
    saveSoon();
    notifyListeners();
    scheduleReminders();
  }

  // ---------------- study time (counted by the strict sessions) ----------------
  void addStudyMs(int ms) {
    _pendingMs += ms;
    if (_pendingMs < 5000) return;
    final k = dayKey(DateTime.now());
    daySecs[k] = (daySecs[k] ?? 0) + _pendingMs ~/ 1000;
    _pendingMs %= 1000;
    saveSoon();
  }

  void addSession() {
    final k = dayKey(DateTime.now());
    daySessions[k] = (daySessions[k] ?? 0) + 1;
    saveSoon();
  }

  int secsOnDay(DateTime d) => daySecs[dayKey(d)] ?? 0;

  /// Consecutive days (ending today, or yesterday if today is still empty) with at least one minute of study
  int get streak {
    var d = dayOnly(DateTime.now());
    if (secsOnDay(d) < 60) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (secsOnDay(d) >= 60) {
      n++;
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return n;
  }

  // ---------------- reminders (scheduled by the Android side, so they work with the app closed) ----------------
  void scheduleReminders() {
    _remTimer?.cancel();
    _remTimer = Timer(const Duration(seconds: 2), _pushReminders);
  }

  int _id(String s) => s.hashCode & 0x3fffffff;

  Future<void> _pushReminders() async {
    final out = <Map<String, Object>>[];
    if (remindersOn) {
      final now = DateTime.now();
      void add(String key, DateTime at, String title, String body) {
        if (at.isAfter(now)) out.add({'id': _id(key), 'at': at.millisecondsSinceEpoch, 'title': title, 'body': body});
      }

      for (final a in agenda()) {
        if (a.done) continue;
        if (a.isExam) {
          final d = dayOnly(a.when);
          add('${a.key}|3d', DateTime(d.year, d.month, d.day - 3, 18), 'امتحان بعد 3 أيام', a.title);
          add('${a.key}|1d', DateTime(d.year, d.month, d.day - 1, 18), 'امتحان غداً', a.title);
        } else {
          add('${a.key}|1d', a.when.subtract(const Duration(days: 1)), 'تسليم غداً', a.title);
          add('${a.key}|3h', a.when.subtract(const Duration(hours: 3)), 'تسليم بعد 3 ساعات', a.title);
        }
      }
      final p = plan();
      for (var i = 0; i < 7; i++) {
        final d = DateTime(now.year, now.month, now.day + i, 17);
        final day = p.where((x) => dayOnly(x.date) == dayOnly(d)).toList();
        final body = day.isEmpty ? 'راجع تقدمك اليوم' : '${day.first.items.length} فيديو في خطة اليوم';
        add('study|${dayKey(d)}', d, 'وقت الدراسة', body);
      }
    }
    try {
      await ch.invokeMethod('setReminders', {'json': jsonEncode(out)});
    } catch (_) {}
  }

  Future<void> askNotifications() async {
    try {
      await ch.invokeMethod('askNotifications');
    } catch (_) {}
  }

  // ---------------- backup / restore / wipe ----------------
  String exportJson() => jsonEncode({
        'v': 1,
        'state': _state(),
        'courses': courses,
        'links': links.map((l) => l.toJson()).toList(),
      });

  Future<bool> importJson(String s) async {
    try {
      final j = jsonDecode(s) as Map;
      if (j['state'] is! Map) return false;
      _apply(j['state'] as Map);
      courses
        ..clear()
        ..addAll({for (final e in ((j['courses'] as Map?) ?? {}).entries) '${e.key}': '${e.value}'});
      links
        ..clear()
        ..addAll(((j['links'] as List?) ?? []).map((e) => MoodleLink.fromJson(e as Map)));
      await _write();
      final d = await _dir();
      await File('$d/moodle_links.json').writeAsString(jsonEncode({
        'at': DateTime.now().toIso8601String(),
        'courses': courses,
        'links': links.map((l) => l.toJson()).toList(),
      }));
      notifyListeners();
      scheduleReminders();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> wipe() async {
    final d = await _dir();
    for (final n in ['study_state.json', 'study_state.json.bak', 'study_state.json.tmp', 'moodle_links.json']) {
      try {
        final f = File('$d/$n');
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    courses.clear();
    links.clear();
    tasks.clear();
    manual.clear();
    feed.clear();
    done.clear();
    dur.clear();
    notes.clear();
    daySecs.clear();
    daySessions.clear();
    examLog.clear();
    await clearLogin();
    deadline = DateTime(2026, 12, 2);
    dailyMinutes = 180;
    scheduleReminders();
    notifyListeners();
  }
}

final study = StudyStore();

// Optional saved Moodle login: kept only if the student chooses to, encrypted by the Android keystore
const _sec = FlutterSecureStorage();

Future<List<String>?> savedLogin() async {
  try {
    final u = await _sec.read(key: 'moodle_user'), p = await _sec.read(key: 'moodle_pass');
    return u == null || p == null ? null : [u, p];
  } catch (_) {
    return null;
  }
}

Future<void> saveLogin(String u, String p) async {
  await _sec.write(key: 'moodle_user', value: u);
  await _sec.write(key: 'moodle_pass', value: p);
}

Future<void> clearLogin() async {
  try {
    await _sec.delete(key: 'moodle_user');
    await _sec.delete(key: 'moodle_pass');
  } catch (_) {}
}

/// Moodle address (the student can change it in the settings)
String get moodleHome => 'https://${study.moodleHost}/';

bool isMoodleHost(String h) {
  final host = study.moodleHost;
  final parts = host.split('.');
  final parent = parts.length > 2 ? parts.skip(1).join('.') : host;
  return h == host || h.endsWith('.$parent');
}
