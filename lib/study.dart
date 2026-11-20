import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'links_page.dart';

/// A review question of a lecture (answer is revealed in the quiz)
class QA {
  String q, a;
  QA(this.q, this.a);
  Map<String, String> toJson() => {'q': q, 'a': a};
  factory QA.fromJson(Map j) => QA('${j['q']}', '${j['a']}');
}

/// The notebook of one lecture: free text + review questions
class Note {
  String text;
  final List<QA> qs;
  Note({this.text = '', List<QA>? qs}) : qs = qs ?? <QA>[];
  bool get isEmpty => text.trim().isEmpty && qs.isEmpty;
  Map<String, dynamic> toJson() => {'n': text, 'q': qs.map((e) => e.toJson()).toList()};
  factory Note.fromJson(Map j) =>
      Note(text: '${j['n'] ?? ''}', qs: ((j['q'] as List?) ?? []).map((e) => QA.fromJson(e as Map)).toList());
}

/// One day of the study plan
class PlanDay {
  final DateTime date;
  final List<MoodleLink> items = [];
  int minutes = 0;
  PlanDay(this.date);
}

/// YouTube id of a link (null for files / playlists / external links)
String? ytId(MoodleLink l) => l.group == 'yt' ? VideoId.parseVideoId(l.url) : null;

/// What counts for progress (documents are tracked but are NOT part of the video plan)
bool countable(MoodleLink l) => const ['yt', 'video', 'pdf', 'doc'].contains(l.group);

/// Key used for "done" marks and notebooks (the same YouTube video shares them between courses)
String linkKey(MoodleLink l) => ytId(l) ?? '${l.cid}|${l.url}';

const _days = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
String dayName(DateTime d) => _days[d.weekday - 1];

/// Everything local on the phone: saved Moodle links, done marks, durations, notebooks, deadline.
/// No server, no AI: the plan is plain arithmetic over the unfinished videos.
class StudyStore extends ChangeNotifier {
  final courses = <String, String>{};
  final links = <MoodleLink>[];
  final done = <String>{};
  final dur = <String, int>{}; // youtube id -> seconds
  final notes = <String, Note>{};
  DateTime deadline = DateTime(2026, 12, 2);
  bool loaded = false, fetching = false;
  int fetched = 0, toFetch = 0;
  Timer? _timer;

  Future<String> _dir() async => (await getApplicationDocumentsDirectory()).path;

  /// Reads the links saved by the Moodle crawler (every call, the crawl may have changed them)
  /// and, once, the study state.
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
      try {
        final f = File('$d/study_state.json');
        if (await f.exists()) {
          final j = jsonDecode(await f.readAsString()) as Map;
          done.addAll(((j['done'] as List?) ?? []).map((e) => '$e'));
          dur.addAll({for (final e in ((j['dur'] as Map?) ?? {}).entries) '${e.key}': (e.value as num).toInt()});
          notes.addAll({for (final e in ((j['notes'] as Map?) ?? {}).entries) '${e.key}': Note.fromJson(e.value as Map)});
          final dl = DateTime.tryParse('${j['deadline']}');
          if (dl != null) deadline = dl;
        }
      } catch (_) {}
      loaded = true;
    }
    notifyListeners();
  }

  void saveSoon() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), _write);
  }

  Future<void> _write() async {
    try {
      await File('${await _dir()}/study_state.json').writeAsString(jsonEncode({
        'deadline': deadline.toIso8601String(),
        'done': done.toList(),
        'dur': dur,
        'notes': {for (final e in notes.entries) if (!e.value.isEmpty) e.key: e.value.toJson()},
      }));
    } catch (_) {}
  }

  // ---- done marks ----
  bool isDone(MoodleLink l) => done.contains(linkKey(l));

  void setDone(MoodleLink l, bool v) {
    if (v) {
      done.add(linkKey(l));
    } else {
      done.remove(linkKey(l));
    }
    saveSoon();
    notifyListeners();
  }

  void toggleDone(MoodleLink l) => setDone(l, !isDone(l));

  void setDeadline(DateTime d) {
    deadline = d;
    saveSoon();
    notifyListeners();
  }

  // ---- progress ----
  List<MoodleLink> countableOf(String cid) => links.where((l) => l.cid == cid && countable(l)).toList();
  int totalOf(String cid) => countableOf(cid).length;
  int doneOf(String cid) => countableOf(cid).where(isDone).length;
  int get totalAll => links.where(countable).length;
  int get doneAll => links.where((l) => countable(l) && isDone(l)).length;

  /// Course ids that have links, in the Moodle order
  List<String> courseIds() {
    final have = links.map((l) => l.cid).toSet();
    return [...courses.keys.where(have.contains), ...have.where((k) => !courses.containsKey(k))];
  }

  // ---- notes ----
  Note? noteOf(MoodleLink l) => notes[linkKey(l)];
  Note ensureNote(MoodleLink l) => notes.putIfAbsent(linkKey(l), () => Note());

  // ---- video plan (YouTube videos only; documents are not part of the plan) ----
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

  /// Spreads the unfinished videos over the days from today to the deadline (same order as Moodle),
  /// about the same number of minutes each day. Recomputed every time, so marking a video done updates it.
  List<PlanDay> plan() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var days = deadline.difference(today).inDays + 1;
    if (days < 1) days = 1;
    final todo = videoLinks().where((l) => !isDone(l)).toList();
    int mins(MoodleLink l) => (secondsOf(l) / 60).ceil();
    final total = todo.fold<int>(0, (s, l) => s + mins(l));
    final target = (total / days).ceil();
    final out = <PlanDay>[];
    var cur = PlanDay(today);
    for (final l in todo) {
      final m = mins(l);
      if (cur.items.isNotEmpty && cur.minutes + m > target && out.length < days - 1) {
        out.add(cur);
        cur = PlanDay(DateTime(today.year, today.month, today.day + out.length));
      }
      cur.items.add(l);
      cur.minutes += m;
    }
    if (cur.items.isNotEmpty) out.add(cur);
    return out;
  }

  /// Reads the real length of each YouTube video once (cached), 4 at a time
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
  }
}

final study = StudyStore();
