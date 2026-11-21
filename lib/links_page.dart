import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'docs.dart';
import 'notebook_page.dart';
import 'preview_page.dart';
import 'storage.dart';
import 'study.dart';
import 'theme.dart';

// JS that runs INSIDE the logged-in Moodle page (keeps the session). It lists all the user's courses,
// then crawls them breadth-first (6 pages at once), reads each page's HTML and posts ONLY links
// (YouTube / files / video / external) through the FLINK channel. Nothing is downloaded.
const crawlJs = r'''
(async function(){
  if (window.__flc) return;
  window.__flc = true; window.__flcCancel = false;
  var P = function(o){ try { FLINK.postMessage(JSON.stringify(o)); } catch(e){} };
  try {
    var base = location.origin;
    var sk = (window.M && M.cfg && M.cfg.sesskey) || "";
    var courses = [];
    // 1) the user's courses through Moodle's own web service
    try {
      var r0 = await fetch(base + "/lib/ajax/service.php?sesskey=" + sk + "&info=core_course_get_enrolled_courses_by_timeline_classification", {
        method: "POST", credentials: "include", headers: {"Content-Type": "application/json"},
        body: JSON.stringify([{index: 0, methodname: "core_course_get_enrolled_courses_by_timeline_classification",
          args: {offset: 0, limit: 0, classification: "all", sort: "fullname"}}])
      });
      var j = await r0.json();
      if (j[0] && j[0].data && j[0].data.courses)
        courses = j[0].data.courses.map(function(c){ return {id: String(c.id), name: c.fullname}; });
    } catch(e) {}
    // 2) fallback: course links visible on the current page
    if (!courses.length) {
      var s0 = {};
      document.querySelectorAll("a[href*=\"/course/view.php?id=\"]").forEach(function(a){
        var m = a.href.match(/id=(\d+)/);
        if (m && !s0[m[1]]) { s0[m[1]] = 1; courses.push({id: m[1], name: (a.textContent || "").replace(/\s+/g, " ").trim() || ("مادة " + m[1])}); }
      });
    }
    if (!courses.length) { P({t: "err", m: "nocourses"}); return; }
    P({t: "courses", list: courses});

    var visited = {}, queue = [], active = 0, count = 0, sent = {};
    var YT = /(?:youtu\.be\/|youtube(?:-nocookie)?\.com\/(?:watch\?(?:[^#]*&)?v=|embed\/|shorts\/|v\/))([\w-]{11})/;
    var YTL = /youtube\.com\/playlist\?list=/;
    function emit(cid, k, title, url, ct, sec) {
      var key = cid + "|" + url; if (sent[key]) return; sent[key] = 1;
      P({t: "link", cid: cid, k: k, title: title, url: url, ct: ct || "", s: sec || ""});
    }
    // name of the course section (chapter / week) that contains an element
    function secOf(e, fb) {
      var s = e.closest && e.closest("li.section,[data-sectionname],section.course-section");
      if (!s) return fb || "";
      var n = s.getAttribute("data-sectionname") || clean(s.querySelector(".sectionname,.section-title,h3"));
      return (n || fb || "").slice(0, 80);
    }
    function clean(el) {
      if (!el) return "";
      var c = el.cloneNode(true);
      c.querySelectorAll(".accesshide,.sr-only").forEach(function(x){ x.remove(); });
      return (c.textContent || "").replace(/\s+/g, " ").trim();
    }
    function fileName(u) { try { return decodeURIComponent(u.split("?")[0].split("/").pop()); } catch(e) { return u; } }
    function follow(u, cid) {
      if (u.indexOf(base) !== 0) return false;
      var m = u.match(/\/course\/view\.php\?(?:.*&)?id=(\d+)/);
      if (m) return m[1] === cid;
      return /\/mod\/(page|folder|book|resource|url|lesson|label|imscp|assign|quiz)\/view\.php/.test(u);
    }
    function push(u, cid, title, sec) {
      u = u.split("#")[0];
      if (visited[u] || count + queue.length > 3000) return;
      visited[u] = 1; queue.push({u: u, cid: cid, title: title, sec: sec || ""});
    }
    courses.forEach(function(c){ push(base + "/course/view.php?id=" + c.id, c.id, c.name, ""); });

    async function visit(it) {
      count++;
      var r;
      try { r = await fetch(it.u, {credentials: "include"}); }
      catch (e) {
        // an external redirect (mod/url) is blocked by CORS: keep the Moodle link, it opens inside the app
        if (/\/mod\/url\/view\.php/.test(it.u)) emit(it.cid, "ext", it.title || it.u, it.u, "", it.sec);
        return;
      }
      var ct = r.headers.get("content-type") || "";
      var fu = r.url;
      if (ct.indexOf("text/html") !== 0) {
        // the page was really a file (mod/resource): record the final file link, do not download it
        if (r.body && r.body.cancel) r.body.cancel();
        if (fu.indexOf("/login/") > -1) return;
        emit(it.cid, ct.indexOf("video/") === 0 ? "video" : "file", it.title || fileName(fu), fu, ct, it.sec);
        return;
      }
      if (fu.indexOf("/login/") > -1) return;
      var html = await r.text();
      var d = new DOMParser().parseFromString(html, "text/html");
      var root = d.querySelector("#region-main") || d.body; // skip the side drawer (it lists every course)
      var pt = (d.title || "").split(":").pop().trim();
      // assignment / quiz page: send its due-date text and submission status (read in the app)
      var tm = it.u.match(/\/mod\/(assign|quiz)\/view\.php/);
      if (tm) {
        var tx = (root.textContent || "").replace(/\s+/g, " ");
        var di = tx.search(/Due\s*:|Closes\s*:|Due date|Close date|موعد التسليم|تاريخ التسليم|يغلق|ينتهي في|تاريخ الاستحقاق|الاستحقاق\s*:/i);
        var sub = null;
        if (tm[1] === "assign") {
          if (/Submitted for grading|تم التسليم|تم تقديم|Graded|تم التقييم/i.test(tx)) sub = true;
          else if (/No submissions? (?:have been made|made) yet|No attempt|لم يتم تقديم|لا توجد محاولات|لم تقم بتسليم/i.test(tx)) sub = false;
        } else {
          if (/Finished|منتهية|Your final grade|الدرجة النهائية/i.test(tx)) sub = true;
        }
        P({t: "task", cid: it.cid, k: tm[1], title: it.title || pt, url: it.u, due: di >= 0 ? tx.substr(di, 140) : "", sub: sub});
      }
      root.querySelectorAll("a[href],iframe[src],iframe[data-src],video[src],video source[src],object[data],embed[src]").forEach(function(e) {
        var raw = e.getAttribute("href") || e.getAttribute("src") || e.getAttribute("data-src") || e.getAttribute("data");
        if (!raw || /^(javascript|mailto|tel|blob|data):|^#/.test(raw)) return;
        var u; try { u = new URL(raw, fu).href; } catch (x) { return; }
        var isA = e.tagName === "A";
        var title = isA ? (clean(e.querySelector(".instancename") || e) || pt) : (e.title || pt);
        var sc = secOf(e, it.sec);
        var m = u.match(YT);
        if (m) { emit(it.cid, "yt", title, "https://m.youtube.com/watch?v=" + m[1], "", sc); return; }
        if (YTL.test(u)) { emit(it.cid, "yt", title, u, "", sc); return; }
        if (/pluginfile\.php/.test(u)) { emit(it.cid, /^(VIDEO|SOURCE)$/.test(e.tagName) ? "video" : "file", isA ? (title || fileName(u)) : fileName(u), u, "", sc); return; }
        if (/^(VIDEO|SOURCE)$/.test(e.tagName)) { emit(it.cid, "video", pt, u, "", sc); return; }
        if (isA) {
          if (follow(u, it.cid)) { push(u, it.cid, title, sc); return; }
          if (/^https?:/.test(u) && u.indexOf(base) !== 0) emit(it.cid, "ext", title || u, u, "", sc);
        } else if (/^https?:/.test(u) && u.indexOf(base) !== 0) {
          emit(it.cid, "ext", title || u, u, "", sc);
        }
      });
    }

    async function worker() {
      while (true) {
        if (window.__flcCancel) return;
        var it = queue.shift();
        if (!it) { if (active === 0) return; await new Promise(function(r){ setTimeout(r, 150); }); continue; }
        active++;
        try { await visit(it); } catch (e) {}
        active--;
        P({t: "prog", v: count, q: queue.length});
      }
    }
    await Promise.all([1, 2, 3, 4, 5, 6].map(worker));
    P({t: "done"});
  } catch (e) {
    P({t: "err", m: String(e)});
  } finally {
    window.__flc = false;
  }
})();
''';

class MoodleLink {
  final String cid, kind, title, url, ct, sec; // sec = chapter / week name in the course
  const MoodleLink(this.cid, this.kind, this.title, this.url, this.ct, [this.sec = '']);

  // yt / pdf / doc / video / file / ext
  String get group {
    if (kind == 'yt' || kind == 'ext') return kind;
    final p = (Uri.tryParse(url)?.path ?? url).toLowerCase();
    if (kind == 'video' || isVideo(p) || ct.startsWith('video/')) return 'video';
    if (p.endsWith('.pdf') || ct.contains('pdf')) return 'pdf';
    if (isDocPath(p)) return 'doc';
    return 'file';
  }

  Map<String, String> toJson() => {'c': cid, 'k': kind, 't': title, 'u': url, 'ct': ct, 's': sec};
  factory MoodleLink.fromJson(Map j) =>
      MoodleLink('${j['c']}', '${j['k']}', '${j['t']}', '${j['u']}', '${j['ct'] ?? ''}', '${j['s'] ?? ''}');
}

/// Collects the links of every Moodle course. Only links are kept (no downloads) and they are
/// saved on the phone so the list is there next time without crawling again.
class LinkCrawler extends ChangeNotifier {
  final WebViewController w;
  LinkCrawler(this.w);

  final courses = <String, String>{}; // course id -> name
  final links = <MoodleLink>[];
  final _seen = <String>{};
  final tasks = <MoodleTask>[]; // assignments / quizzes found by this crawl
  Set<String> _prev = {};
  bool running = false;
  int visited = 0, queued = 0;
  String? error;
  DateTime? savedAt;
  Timer? _t;
  bool _dead = false;

  // Coalesce thousands of messages into a few rebuilds
  void _poke() => _t ??= Timer(const Duration(milliseconds: 300), () {
        _t = null;
        notifyListeners();
      });

  Future<File> _file() async => File('${(await getApplicationDocumentsDirectory()).path}/moodle_links.json');

  Future<void> load() async {
    if (running) return;
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map;
      courses
        ..clear()
        ..addAll({for (final e in (j['courses'] as Map).entries) '${e.key}': '${e.value}'});
      links
        ..clear()
        ..addAll((j['links'] as List).map((e) => MoodleLink.fromJson(e as Map)));
      _seen
        ..clear()
        ..addAll(links.map((l) => '${l.cid}|${l.url}'));
      savedAt = DateTime.tryParse('${j['at']}');
      notifyListeners();
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      savedAt = DateTime.now();
      await (await _file()).writeAsString(jsonEncode({
        'at': savedAt!.toIso8601String(),
        'courses': courses,
        'links': links.map((l) => l.toJson()).toList(),
      }));
    } catch (_) {}
  }

  Future<void> start() async {
    if (running) return;
    running = true;
    error = null;
    visited = 0;
    queued = 0;
    _prev = links.map((l) => '${l.cid}|${l.url}').toSet();
    tasks.clear();
    courses.clear();
    links.clear();
    _seen.clear();
    notifyListeners();
    await w.runJavaScript(crawlJs);
  }

  void stop() {
    w.runJavaScript('window.__flcCancel = true;');
  }

  void onMessage(String s) {
    if (_dead) return;
    Map m;
    try {
      m = jsonDecode(s) as Map;
    } catch (_) {
      return;
    }
    switch (m['t']) {
      case 'courses':
        for (final c in m['list'] as List) {
          courses['${c['id']}'] = '${c['name']}';
        }
        break;
      case 'link':
        final l = MoodleLink('${m['cid']}', '${m['k']}', '${m['title']}', '${m['url']}', '${m['ct'] ?? ''}', '${m['s'] ?? ''}');
        if (_seen.add('${l.cid}|${l.url}')) links.add(l);
        break;
      case 'task':
        final raw = '${m['due'] ?? ''}';
        tasks.add(MoodleTask('${m['cid']}', '${m['k']}', '${m['title']}', '${m['url']}', raw, parseMoodleDate(raw), m['sub'] as bool?));
        break;
      case 'prog':
        visited = (m['v'] as num).toInt();
        queued = (m['q'] as num).toInt();
        break;
      case 'done':
        running = false;
        save();
        study.recordCrawl(links.where((l) => !_prev.contains('${l.cid}|${l.url}')).toList(), List.of(tasks),
            first: _prev.isEmpty);
        break;
      case 'err':
        running = false;
        error = '${m['m']}';
        load(); // keep the last saved list
        break;
    }
    if (m['t'] == 'done' || m['t'] == 'err') {
      _t?.cancel();
      _t = null;
      notifyListeners();
    } else {
      _poke();
    }
  }

  @override
  void dispose() {
    _dead = true;
    _t?.cancel();
    super.dispose();
  }
}

IconData groupIcon(String g) => switch (g) {
      'yt' => Icons.smart_display,
      'pdf' => Icons.picture_as_pdf,
      'doc' => Icons.description_outlined,
      'video' => Icons.play_circle_outline,
      'file' => Icons.insert_drive_file_outlined,
      _ => Icons.link,
    };

const _groups = <String, String>{
  'all': 'الكل',
  'yt': 'يوتيوب',
  'pdf': 'PDF',
  'doc': 'مستندات',
  'video': 'فيديو',
  'file': 'ملفات',
  'ext': 'روابط خارجية',
};

/// Shows the extracted links inside the app: grouped by course, filter + search.
class LinksPage extends StatefulWidget {
  final LinkCrawler crawler;
  final bool Function() onMoodle; // is the Moodle browser on a university page?
  final void Function(String url) onOpenDoc; // opens a document in the in-app viewer
  const LinksPage({super.key, required this.crawler, required this.onMoodle, required this.onOpenDoc});
  @override
  State<LinksPage> createState() => _LinksPageState();
}

class _LinksPageState extends State<LinksPage> {
  String filter = 'all', query = '';

  LinkCrawler get c => widget.crawler;

  @override
  void initState() {
    super.initState();
    c.load();
    study.load();
  }

  void toast(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _start() async {
    if (!widget.onMoodle()) {
      toast('افتح المودل وسجّل الدخول أولاً');
      return;
    }
    await c.start();
  }

  void _open(MoodleLink l) {
    switch (l.group) {
      case 'yt':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => PreviewPage(url: l.url, title: l.title, youtubeId: VideoId.parseVideoId(l.url))));
        break;
      case 'pdf':
      case 'doc':
        toast('جاري فتح المستند...');
        widget.onOpenDoc(l.url);
        break;
      case 'file':
        Clipboard.setData(ClipboardData(text: l.url));
        toast('هذا النوع لا يُعرض داخل التطبيق — نُسخ الرابط');
        break;
      default:
        Navigator.push(context, MaterialPageRoute(builder: (_) => PreviewPage(url: l.url, title: l.title)));
    }
  }

  IconData _icon(String g) => groupIcon(g);

  @override
  Widget build(BuildContext ctx) => AnimatedBuilder(
        animation: Listenable.merge([c, study]),
        builder: (_, __) {
          final q = query.trim().toLowerCase();
          final counts = <String, int>{'all': c.links.length};
          for (final l in c.links) {
            counts[l.group] = (counts[l.group] ?? 0) + 1;
          }
          bool ok(MoodleLink l) =>
              (filter == 'all' || l.group == filter) &&
              (q.isEmpty || l.title.toLowerCase().contains(q) || l.url.toLowerCase().contains(q));
          final byCourse = <String, List<MoodleLink>>{};
          for (final l in c.links.where(ok)) {
            byCourse.putIfAbsent(l.cid, () => []).add(l);
          }
          final order = [...c.courses.keys.where(byCourse.containsKey), ...byCourse.keys.where((k) => !c.courses.containsKey(k))];
          return Scaffold(
            appBar: AppBar(
              title: const Row(children: [Icon(Icons.link, color: kAccent), SizedBox(width: 10), Text('روابط المودل')]),
              actions: [
                c.running
                    ? IconButton(tooltip: 'إيقاف', icon: const Icon(Icons.stop_circle_outlined), onPressed: c.stop)
                    : IconButton(tooltip: 'استخراج الروابط', icon: const Icon(Icons.refresh), onPressed: _start),
              ],
            ),
            body: Column(children: [
              if (c.running) ...[
                const LinearProgressIndicator(color: kAccent),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('جاري الفحص... ${c.visited} صفحة · ${c.links.length} رابط · ${c.courses.length} مادة',
                      style: const TextStyle(color: Colors.white70)),
                ),
              ] else if (c.error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                      c.error == 'nocourses'
                          ? 'لم أجد موادك. سجّل الدخول من صفحة المودل ثم أعد المحاولة'
                          : 'توقف الاستخراج: ${c.error}',
                      style: const TextStyle(color: kAccent)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: TextField(
                  onChanged: (v) => setState(() => query = v),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث في الروابط'),
                ),
              ),
              SizedBox(
                height: 52,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
                  for (final e in _groups.entries)
                    if (e.key == 'all' || (counts[e.key] ?? 0) > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: ChoiceChip(
                          label: Text('${e.value} (${counts[e.key] ?? 0})'),
                          selected: filter == e.key,
                          onSelected: (_) => setState(() => filter = e.key),
                        ),
                      ),
                ]),
              ),
              Expanded(
                child: c.links.isEmpty && !c.running
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.travel_explore, size: 56, color: Colors.white38),
                            const SizedBox(height: 12),
                            const Text('يقرأ التطبيق صفحات كل موادك ويستخرج الروابط فقط (يوتيوب، ملفات، فيديو) ويعرضها هنا',
                                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                                onPressed: _start, icon: const Icon(Icons.download_for_offline), label: const Text('ابدأ استخراج الروابط')),
                          ]),
                        ),
                      )
                    : ListView(children: [
                        for (final id in order)
                          ExpansionTile(
                            key: ValueKey('$id|$filter|$q'),
                            initiallyExpanded: q.isNotEmpty || filter != 'all',
                            title: Text(c.courses[id] ?? 'مادة $id', maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                '${byCourse[id]!.length} رابط · منجز ${byCourse[id]!.where((l) => countable(l) && study.isDone(l)).length}/${byCourse[id]!.where(countable).length}',
                                style: const TextStyle(color: Colors.white54)),
                            children: [
                              for (final l in byCourse[id]!)
                                ListTile(
                                  dense: true,
                                  leading: Icon(_icon(l.group), color: l.group == 'yt' ? kAccent : null),
                                  title: Text(l.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(_groups[l.group] ?? '', style: const TextStyle(color: Colors.white54)),
                                  trailing: countable(l)
                                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                                          IconButton(
                                            tooltip: 'الدفتر',
                                            icon: Icon(Icons.edit_note, color: (study.noteOf(l)?.isEmpty ?? true) ? null : kAccent),
                                            onPressed: () => Navigator.push(
                                                context, MaterialPageRoute(builder: (_) => NotebookPage(link: l))),
                                          ),
                                          Checkbox(value: study.isDone(l), onChanged: (_) => study.toggleDone(l)),
                                        ])
                                      : null,
                                  onTap: () => _open(l),
                                  onLongPress: () {
                                    Clipboard.setData(ClipboardData(text: l.url));
                                    toast('تم نسخ الرابط');
                                  },
                                ),
                            ],
                          ),
                      ]),
              ),
            ]),
          );
        },
      );
}
