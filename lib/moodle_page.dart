import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'browser_page.dart';
import 'channel.dart';
import 'docs.dart';
import 'preview_page.dart';
import 'theme.dart';
import 'web_fs.dart';
import 'lock_setup.dart';
import 'storage.dart';
import 'strict_shell.dart';

const moodleHome = 'https://moodle.ucas.edu.ps/';

// Only the university domain is allowed (subdomains kept for single sign-on)
bool isMoodle(String url) {
  final h = Uri.tryParse(url)?.host ?? '';
  return h == 'moodle.ucas.edu.ps' || h.endsWith('.ucas.edu.ps');
}

// Finds the video on the current Moodle page (<video>, <source>, or a direct file link)
const findVideoJs = '''
(function(){
  var v = document.querySelector('video'), src = null;
  if (v) src = v.currentSrc || v.src || (v.querySelector('source') || {}).src;
  if (!src) {
    var a = document.querySelector('a[href*="pluginfile.php"][href\$=".mp4"], a[href*="pluginfile.php"][href\$=".webm"]');
    if (a) src = a.href;
  }
  if (!src || src.indexOf('blob:') === 0)
    return JSON.stringify({err: src ? 'blob' : (document.querySelector('iframe') ? 'iframe' : 'none')});
  return JSON.stringify({url: src, title: document.title});
})()
''';

// Decode the string returned by runJavaScriptReturningResult
dynamic decodeJs(Object r) {
  var s = r.toString();
  if (s == 'null') return null;
  var d = jsonDecode(s);
  if (d is String) d = jsonDecode(d);
  return d;
}

// JS that runs INSIDE the Moodle page (so it keeps the login session) and streams a file to Flutter.
// doc == true: html pages are not files -> report them back ('H'), or resolve the real
// file link of a Moodle "resource" page ('R'); videos are left to the normal page ('H').
const _fetchFn = r"""async function(url, doc){
  try {
    const r = await fetch(url, {credentials: 'include'});
    if (!r.ok) { FLDL.postMessage('X|HTTP ' + r.status); return; }
    const ct = r.headers.get('content-type') || '';
    if (doc && (ct.indexOf('text/html') === 0 || ct.indexOf('video/') === 0)) {
      if (ct.indexOf('text/html') === 0 && url.indexOf('/mod/resource/') > -1) {
        const t = await r.text();
        const m = t.match(/https?:[^"'<>\s]+pluginfile\.php[^"'<>\s]+/);
        if (m) { FLDL.postMessage('R|' + m[0].replace(/&amp;/g, '&')); return; }
      }
      FLDL.postMessage('H|' + r.url); return;
    }
    FLDL.postMessage('S|' + (r.headers.get('content-length') || '0') + '|' + ct + '|' + r.url + '|' + (r.headers.get('content-disposition') || ''));
    const rd = r.body.getReader();
    while (true) {
      const {done, value} = await rd.read();
      if (done) break;
      let bin = ''; const step = 0x8000;
      for (let i = 0; i < value.length; i += step) bin += String.fromCharCode.apply(null, value.subarray(i, i + step));
      FLDL.postMessage('C|' + btoa(bin));
    }
    FLDL.postMessage('E|');
  } catch (e) { FLDL.postMessage('X|' + e); }
}""";

String fetchJs(String url, bool doc) => '($_fetchFn)(${jsonEncode(url)}, $doc);';

// Links that should open as a document inside the app
bool isDocLink(String url) {
  final u = Uri.tryParse(url);
  if (u == null) return false;
  final p = u.path.toLowerCase();
  if (isVideo(p)) return false;
  return isDocPath(p) || p.contains('/mod/resource/view.php');
}

// File name from Content-Disposition, or the last URL segment
Future<File> newDocFile(String finalUrl, String ct, String disp) async {
  var name = '';
  try {
    final m = RegExp(r"filename\*=UTF-8''([^;]+)", caseSensitive: false).firstMatch(disp);
    final m2 = RegExp(r'filename="?([^";]+)"?', caseSensitive: false).firstMatch(disp);
    if (m != null) {
      name = Uri.decodeComponent(m.group(1)!);
    } else if (m2 != null) {
      name = m2.group(1)!;
    } else {
      final segs = Uri.parse(finalUrl).pathSegments;
      name = segs.isEmpty ? 'document' : segs.last;
    }
  } catch (_) {}
  name = safeName(name);
  if (name.isEmpty) name = 'document';
  if (!isDocPath(name)) name += extFromContentType(ct);
  return File('${(await docsRoot()).path}/$name');
}

/// Moodle browser (university domain only) with download + strict mode.
/// YouTube links open in the in-app YouTube browser; documents open in the in-app viewer.
class MoodlePage extends StatefulWidget {
  const MoodlePage({super.key});
  @override
  State<MoodlePage> createState() => _MoodlePageState();
}

class _MoodlePageState extends State<MoodlePage> {
  late final WebViewController w;
  String url = moodleHome;
  final progress = ValueNotifier<String>('');
  IOSink? sink;
  File? outFile;
  int total = 0, got = 0;
  bool docMode = false, resolved = false;
  String? docUrl;
  final bypass = <String>{}; // urls the page may load once without being intercepted
  Future<void> _q = Future.value(); // chunks are handled strictly in order

  @override
  void initState() {
    super.initState();
    w = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Receives files in chunks from the page (uses the page's login session)
      ..addJavaScriptChannel('FLDL', onMessageReceived: (m) {
        _q = _q.then((_) => onChunk(m.message)).catchError((_) {});
      })
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) {
          if (!r.isMainFrame) return NavigationDecision.navigate;
          if (isYoutube(r.url)) {
            openYoutube(r.url);
            return NavigationDecision.prevent;
          }
          if (!isMoodle(r.url)) return NavigationDecision.prevent;
          if (bypass.remove(r.url)) return NavigationDecision.navigate;
          if (isDocLink(r.url)) {
            openDoc(r.url);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onUrlChange: (c) => url = c.url ?? url,
        onPageFinished: (_) => bypass.clear(),
      ))
      ..loadRequest(Uri.parse(moodleHome));
  }

  void toast(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  // ---- YouTube link inside Moodle -> in-app YouTube browser ----
  void openYoutube(String u) {
    String target = u;
    final id = VideoId.parseVideoId(u);
    if (id != null) target = 'https://m.youtube.com/watch?v=$id';
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => BrowserPage(initialUrl: target)));
  }

  // ---- Document link -> download with the Moodle session -> in-app viewer ----
  Future<void> openDoc(String u) async {
    if (progress.value.isNotEmpty) return;
    docMode = true;
    resolved = false;
    docUrl = u;
    total = 0;
    got = 0;
    progress.value = 'جاري فتح المستند...';
    await w.runJavaScript(fetchJs(u, true));
  }

  Future<Map?> findVideo() async {
    final r = await w.runJavaScriptReturningResult(findVideoJs);
    final m = decodeJs(r) as Map?;
    if (m == null || m['url'] == null) {
      toast(m?['err'] == 'iframe'
          ? 'الفيديو مضمّن من منصة خارجية ولا يمكن تحميله من هنا'
          : m?['err'] == 'blob'
              ? 'هذا الفيديو بث محمي ولا يمكن تحميله'
              : 'لم أجد فيديو في هذه الصفحة. افتح الفيديو أولاً');
      return null;
    }
    return m;
  }

  // ---- Download the video of the current page ----
  Future<void> download() async {
    final v = await findVideo();
    if (v == null || !mounted) return;
    final dir = await chooseFolder(context);
    if (dir == null) return;
    final vurl = v['url'] as String;
    final path = Uri.parse(vurl).path;
    final ext = isVideo(path) ? path.substring(path.lastIndexOf('.')) : '.mp4';
    var name = safeName((v['title'] as String?) ?? 'video');
    if (name.isEmpty) name = 'video';
    var f = File('${dir.path}/$name$ext');
    if (await f.exists()) f = File('${dir.path}/$name-${DateTime.now().millisecondsSinceEpoch}$ext');
    outFile = f;
    sink = f.openWrite();
    docMode = false;
    total = 0;
    got = 0;
    progress.value = 'جاري التحضير...';
    await w.runJavaScript(fetchJs(vurl, false));
  }

  Future<void> onChunk(String msg) async {
    final kind = msg[0], body = msg.length > 2 ? msg.substring(2) : '';
    if (kind == 'R') {
      // a Moodle resource page pointing to the real file: fetch that file instead
      if (!resolved && docUrl != null) {
        resolved = true;
        docUrl = body;
        await w.runJavaScript(fetchJs(body, true));
        return;
      }
      loadRaw();
    } else if (kind == 'H') {
      // not a file (normal page / video): let the WebView show it
      loadRaw(extra: body);
    } else if (kind == 'S') {
      final p = body.split('|');
      total = int.tryParse(p[0]) ?? 0;
      if (docMode) {
        final f = await newDocFile(p.length > 2 ? p[2] : docUrl!, p.length > 1 ? p[1] : '',
            p.length > 3 ? p.sublist(3).join('|') : '');
        outFile = f;
        sink = f.openWrite();
      }
    } else if (kind == 'C') {
      final bytes = base64Decode(body);
      sink?.add(bytes);
      got += bytes.length;
      progress.value = total > 0
          ? 'تحميل ${(got * 100 / total).toStringAsFixed(0)}%'
          : 'تحميل ${(got / 1048576).toStringAsFixed(0)}MB';
    } else if (kind == 'E') {
      await sink?.close();
      sink = null;
      progress.value = '';
      if (docMode) {
        if (mounted && outFile != null) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => DocViewerPage(path: outFile!.path)));
        }
      } else {
        toast('تم التحميل');
      }
    } else if (kind == 'X') {
      await sink?.close();
      sink = null;
      try {
        await outFile?.delete();
      } catch (_) {}
      progress.value = '';
      if (docMode) {
        loadRaw(); // fetch failed (e.g. redirect to another site): let the page load normally
      } else {
        toast('فشل التحميل: $body');
      }
    }
  }

  // Load the original link in the WebView without intercepting it again
  void loadRaw({String? extra}) {
    progress.value = '';
    final u = docUrl;
    if (u == null) return;
    bypass.add(u);
    if (extra != null) bypass.add(extra);
    w.loadRequest(Uri.parse(u));
  }

  // ---- Preview: list the YouTube links / videos / players on this page and open them unlocked ----
  static const _previewJs = r'''
(function(){
  var out = [], seen = {};
  function add(kind, title, url){ if(!url || seen[url]) return; seen[url]=1; out.push({kind:kind,title:title,url:url}); }
  document.querySelectorAll('iframe').forEach(function(f){
    var s = f.src || f.getAttribute('data-src') || '';
    if (!s) return;
    var m = s.match(/youtube(?:-nocookie)?\.com\/embed\/([\w-]{11})/);
    if (m) add('yt', f.title || 'فيديو يوتيوب', 'https://m.youtube.com/watch?v=' + m[1]);
    else add('frame', f.title || 'مشغّل مضمّن', s);
  });
  document.querySelectorAll('a[href]').forEach(function(a){
    if (/youtu\.be\/|youtube\.com\/(watch|shorts)/.test(a.href)) add('yt', (a.textContent||'').trim() || 'رابط يوتيوب', a.href);
  });
  document.querySelectorAll('video').forEach(function(v){
    var s = v.currentSrc || v.src || (v.querySelector('source')||{}).src;
    if (s && s.indexOf('blob:') !== 0) add('video', 'فيديو الصفحة', s);
  });
  return JSON.stringify(out);
})()
''';

  Future<void> preview() async {
    List items = [];
    try {
      final r = await w.runJavaScriptReturningResult(_previewJs);
      var t = r.toString();
      if (t.startsWith('"')) t = jsonDecode(t) as String;
      items = jsonDecode(t) as List;
    } catch (_) {}
    if (!mounted) return;
    if (items.isEmpty) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => PreviewPage(url: url.split('#').first)));
      return;
    }
    final pick = await showModalBottomSheet<Map>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('معاينة فيديوهات الصفحة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final it in items)
                ListTile(
                  leading: Icon(it['kind'] == 'yt' ? Icons.smart_display : Icons.play_circle_outline,
                      color: it['kind'] == 'yt' ? kAccent : null),
                  title: Text('${it['title']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(it['kind'] == 'yt' ? 'يوتيوب' : (it['kind'] == 'video' ? 'فيديو' : 'مشغّل خارجي'),
                      style: const TextStyle(color: Colors.white54)),
                  onTap: () => Navigator.pop(ctx, it),
                ),
              ListTile(
                leading: const Icon(Icons.open_in_full),
                title: const Text('معاينة الصفحة كاملة'),
                onTap: () => Navigator.pop(ctx, {'kind': 'page', 'url': url.split('#').first}),
              ),
            ]),
          ),
        ]),
      ),
    );
    if (pick == null || !mounted) return;
    final u = pick['url'] as String;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => pick['kind'] == 'yt' ? BrowserPage(initialUrl: u) : PreviewPage(url: u)));
  }

  // ---- Strict mode on the current Moodle video page ----
  Future<void> startStrict() async {
    final r = await w.runJavaScriptReturningResult("(document.querySelector('video')||{}).duration || 0");
    final s = double.tryParse(r.toString().replaceAll('"', ''));
    if (s == null || s.isNaN || s.isInfinite || s <= 0) {
      toast('افتح الفيديو وانتظر حتى يحمل ثم حاول');
      return;
    }
    final d = Duration(seconds: s.ceil());
    if (!mounted || !await ensureLockReady(context)) return;
    final extra = await confirmStrict(context, d);
    if (extra == null) return;
    final target = url.split('#').first;
    final end = DateTime.now().add(d + Duration(minutes: extra)).millisecondsSinceEpoch;
    await ch.invokeMethod('startLock', {'end': end, 'type': 'moodle', 'target': target});
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => StrictMoodlePage(url: target, endMillis: end)));
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(
          title: const Row(children: [
            Icon(Icons.school, color: kAccent),
            SizedBox(width: 10),
            Text('المودل'),
          ]),
          actions: [
            IconButton(
              tooltip: 'المستندات',
              icon: const Icon(Icons.description_outlined),
              onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const DocsPage())),
            ),
          ],
        ),
        body: Column(children: [
          Expanded(child: FsWebView(w)),
          Container(
            color: kSurface,
            padding: const EdgeInsets.all(8),
            child: ValueListenableBuilder(
              valueListenable: progress,
              builder: (_, String p, __) => Row(children: [
                IconButton(
                  tooltip: 'رجوع',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () async {
                    if (await w.canGoBack()) w.goBack();
                  },
                ),
                IconButton(
                  tooltip: 'معاينة الفيديوهات',
                  icon: const Icon(Icons.visibility),
                  onPressed: preview,
                ),
                const SizedBox(width: 4),
                Expanded(
                    child: FilledButton.icon(
                        onPressed: startStrict, icon: const Icon(Icons.lock), label: const Text('الوضع الصارم'))),
                const SizedBox(width: 8),
                Expanded(
                    child: FilledButton.tonalIcon(
                        onPressed: p.isEmpty ? download : null,
                        icon: const Icon(Icons.download),
                        label: Text(p.isEmpty ? 'تحميل' : p))),
              ]),
            ),
          ),
        ]),
      );
}

/// Strict mode locked to ONE Moodle page (the video page)
class StrictMoodlePage extends StatefulWidget {
  final String url;
  final int endMillis;
  const StrictMoodlePage({super.key, required this.url, required this.endMillis});
  @override
  State<StrictMoodlePage> createState() => _StrictMoodlePageState();
}

class _StrictMoodlePageState extends State<StrictMoodlePage> {
  late final WebViewController w;

  // Kills link clicks and forces the page back if anything navigates away
  String get lockJs => '''
(function(){
  if (window.__fl) return; window.__fl = true;
  var base = ${jsonEncode(widget.url)};
  document.addEventListener('click', function(e){
    var a = e.target.closest && e.target.closest('a');
    if (a) { e.preventDefault(); e.stopPropagation(); }
  }, true);
  setInterval(function(){
    if (location.href.split('#')[0] !== base) location.replace(base);
  }, 500);
  var v = document.querySelector('video'); if (v) v.play().catch(function(){});
})();
''';

  @override
  void initState() {
    super.initState();
    w = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        // Main frame: only the locked page. Embedded frames (players) are allowed.
        onNavigationRequest: (r) => !r.isMainFrame || r.url.split('#').first == widget.url
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
        onPageFinished: (_) => w.runJavaScript(lockJs),
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext c) =>
      StrictShell(endMillis: widget.endMillis, child: FsWebView(w, strict: true));
}
