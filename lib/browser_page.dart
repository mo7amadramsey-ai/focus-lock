import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'channel.dart';
import 'strict_shell.dart';

// Only these domains may ever load. Anything else is blocked.
bool isYoutube(String url) {
  final h = Uri.tryParse(url)?.host ?? '';
  return h == 'youtube.com' || h.endsWith('.youtube.com') || h == 'youtu.be';
}

/// Normal YouTube-only browser. Used before strict mode starts.
class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});
  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  late final WebViewController w;
  String url = '';
  final progress = ValueNotifier<String>('');

  bool get onVideo => url.contains('watch?v=') || url.contains('youtu.be/');

  @override
  void initState() {
    super.initState();
    w = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        // Block everything that is not YouTube
        onNavigationRequest: (r) =>
            isYoutube(r.url) || r.url == 'about:blank' ? NavigationDecision.navigate : NavigationDecision.prevent,
        onUrlChange: (c) => setState(() => url = c.url ?? ''),
      ))
      ..loadRequest(Uri.parse('https://m.youtube.com'));
  }

  // Read the real video length from the page's <video> element
  Future<Duration?> videoDuration() async {
    final r = await w.runJavaScriptReturningResult("(document.querySelector('video')||{}).duration || 0");
    final s = double.tryParse(r.toString().replaceAll('"', ''));
    if (s == null || s.isNaN || s <= 0) return null;
    return Duration(seconds: s.ceil());
  }

  Future<void> startStrict() async {
    final d = await videoDuration();
    if (!mounted) return;
    if (d == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('انتظر حتى يحمل الفيديو ثم حاول')));
      return;
    }
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
    // Lock to this exact video
    final id = VideoId.parseVideoId(url);
    final target = 'https://m.youtube.com/watch?v=$id';
    final end = DateTime.now().add(d).millisecondsSinceEpoch;
    await ch.invokeMethod('startLock', {'end': end, 'type': 'web', 'target': target});
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => StrictWebPage(url: target, endMillis: end)));
  }

  // Download the current video into the app folder
  Future<void> download() async {
    final yt = YoutubeExplode();
    try {
      final id = VideoId(url);
      progress.value = 'جاري التحضير...';
      final video = await yt.videos.get(id);
      final manifest = await yt.videos.streamsClient.getManifest(id);
      final info = manifest.muxed.withHighestBitrate(); // video + audio in one file
      final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/videos');
      await dir.create(recursive: true);
      final safe = video.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final out = File('${dir.path}/$safe.mp4').openWrite();
      final total = info.size.totalBytes;
      var got = 0;
      await for (final chunk in yt.videos.streamsClient.get(info)) {
        out.add(chunk);
        got += chunk.length;
        progress.value = 'تحميل ${(got * 100 / total).toStringAsFixed(0)}%';
      }
      await out.close();
      progress.value = '';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم التحميل')));
      }
    } catch (e) {
      progress.value = '';
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التحميل: $e')));
    } finally {
      yt.close();
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('يوتيوب')),
        body: Column(children: [
          Expanded(child: WebViewWidget(controller: w)),
          if (onVideo)
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

/// Strict YouTube page: locked to ONE video. Cannot open anything else.
class StrictWebPage extends StatefulWidget {
  final String url;
  final int endMillis;
  const StrictWebPage({super.key, required this.url, required this.endMillis});
  @override
  State<StrictWebPage> createState() => _StrictWebPageState();
}

class _StrictWebPageState extends State<StrictWebPage> {
  late final WebViewController w;
  late final String id = VideoId.parseVideoId(widget.url)!;

  // Injected into the page: hides navigation UI, kills link clicks,
  // and forces the page back to the locked video if YouTube navigates away
  String get lockJs => '''
(function(){
  if (window.__fl) return; window.__fl = true;
  var id = '$id', base = '${widget.url}';
  var st = document.createElement('style');
  st.textContent = 'ytm-pivot-bar-renderer,ytm-mobile-topbar-renderer,ytm-item-section-renderer,'
    + 'ytm-related-chip-cloud-renderer,ytm-comments-entry-point-header-renderer,'
    + 'ytm-companion-slot,ytm-rich-section-renderer,.related-chips-slot-wrapper{display:none!important}';
  document.head.appendChild(st);
  document.addEventListener('click', function(e){
    if (e.target.closest && e.target.closest('a')) { e.preventDefault(); e.stopPropagation(); }
  }, true);
  setInterval(function(){
    if (location.href.indexOf('v=' + id) < 0) location.replace(base);
  }, 500);
})();
''';

  @override
  void initState() {
    super.initState();
    w = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        // Only the locked video is allowed
        onNavigationRequest: (r) => isYoutube(r.url) && r.url.contains('v=$id')
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
