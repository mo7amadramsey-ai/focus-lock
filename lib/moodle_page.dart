import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'channel.dart';
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

/// Moodle browser (university domain only) with download + strict mode
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

  @override
  void initState() {
    super.initState();
    w = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Receives the downloaded video in chunks from the page (uses the page's login session)
      ..addJavaScriptChannel('FLDL', onMessageReceived: (m) => onChunk(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) =>
            !r.isMainFrame || isMoodle(r.url) ? NavigationDecision.navigate : NavigationDecision.prevent,
        onUrlChange: (c) => url = c.url ?? url,
      ))
      ..loadRequest(Uri.parse(moodleHome));
  }

  void toast(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
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

  // ---- Download ----
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
    total = 0;
    got = 0;
    progress.value = 'جاري التحضير...';
    // fetch inside the page (keeps the Moodle login) and stream chunks to Flutter
    await w.runJavaScript('''
(async function(url){
  try {
    const r = await fetch(url, {credentials: 'include'});
    if (!r.ok) { FLDL.postMessage('X|HTTP ' + r.status); return; }
    FLDL.postMessage('S|' + (r.headers.get('content-length') || '0'));
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
})(${jsonEncode(vurl)});
''');
  }

  Future<void> onChunk(String msg) async {
    final kind = msg[0], body = msg.substring(2);
    if (kind == 'S') {
      total = int.tryParse(body) ?? 0;
    } else if (kind == 'C') {
      final bytes = base64Decode(body);
      sink?.add(bytes);
      got += bytes.length;
      progress.value = total > 0 ? 'تحميل ${(got * 100 / total).toStringAsFixed(0)}%' : 'تحميل ${(got / 1048576).toStringAsFixed(0)}MB';
    } else if (kind == 'E') {
      await sink?.close();
      sink = null;
      progress.value = '';
      toast('تم التحميل');
    } else if (kind == 'X') {
      await sink?.close();
      sink = null;
      try { await outFile?.delete(); } catch (_) {}
      progress.value = '';
      toast('فشل التحميل: $body');
    }
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('بدء الوضع الصارم'),
        content: Text('سيُقفل الهاتف ${d.inMinutes} دقيقة (مدة الفيديو) ولا يمكن الخروج قبل انتهائها.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ابدأ')),
        ],
      ),
    );
    if (ok != true) return;
    final target = url.split('#').first;
    final end = DateTime.now().add(d).millisecondsSinceEpoch;
    await ch.invokeMethod('startLock', {'end': end, 'type': 'moodle', 'target': target});
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => StrictMoodlePage(url: target, endMillis: end)));
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('المودل')),
        body: Column(children: [
          Expanded(child: WebViewWidget(controller: w)),
          Padding(
            padding: const EdgeInsets.all(8),
            child: ValueListenableBuilder(
              valueListenable: progress,
              builder: (_, String p, __) => Row(children: [
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
      StrictShell(endMillis: widget.endMillis, child: WebViewWidget(controller: w));
}
