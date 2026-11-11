import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'channel.dart';
import 'downloads.dart';
import 'storage.dart';
import 'lock_setup.dart';
import 'strict_shell.dart';
import 'theme.dart';
import 'web_fs.dart';

// Only these domains may ever load. Anything else is blocked.
bool isYoutube(String url) {
  final h = Uri.tryParse(url)?.host ?? '';
  return h == 'youtube.com' || h.endsWith('.youtube.com') || h == 'youtu.be';
}

// Google sign-in pages (so you can log in to YouTube inside the app)
bool isSignIn(String url) {
  final u = Uri.tryParse(url);
  if (u == null) return false;
  final h = u.host;
  if (h == 'accounts.google.com' || h == 'consent.google.com' || h == 'accounts.youtube.com' ||
      h == 'myaccount.google.com' || h.startsWith('accounts.google.')) {
    return true;
  }
  if ((h == 'www.google.com' || h == 'google.com') &&
      (u.path.startsWith('/accounts') || u.path.startsWith('/signin') || u.path.startsWith('/recaptcha'))) {
    return true;
  }
  return false;
}

const loginUrl = 'https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fm.youtube.com%2F';

/// Normal YouTube-only browser. Used before strict mode starts.
class BrowserPage extends StatefulWidget {
  final String? initialUrl; // e.g. a YouTube link opened from Moodle
  const BrowserPage({super.key, this.initialUrl});
  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  late final WebViewController w;
  String url = '';

  bool get onVideo => url.contains('watch?v=') || url.contains('youtu.be/');

  @override
  void initState() {
    super.initState();
    w = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kChromeUA)
      ..setNavigationDelegate(NavigationDelegate(
        // Only YouTube + Google sign-in. Embedded frames (captcha etc.) are allowed.
        onNavigationRequest: (r) => !r.isMainFrame || isYoutube(r.url) || isSignIn(r.url) || r.url == 'about:blank'
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
        onUrlChange: (c) => setState(() => url = c.url ?? ''),
      ))
      ..loadRequest(Uri.parse(widget.initialUrl ?? 'https://m.youtube.com'));
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
    if (!await ensureLockReady(context)) return; // strong lock must be enabled first
    final extra = await confirmStrict(context, d);
    if (extra == null) return;
    // Lock to this exact video
    final id = VideoId.parseVideoId(url);
    final target = 'https://m.youtube.com/watch?v=$id';
    final left = lockMs(d, extra); // never more than one hour
    await ch.invokeMethod('startLock', {'left': left, 'type': 'web', 'target': target});
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => StrictWebPage(url: target, leftMs: left)));
  }

  // Add the current video to the downloads list (several can run at once)
  Future<void> download() async {
    final dir = await chooseFolder(context); // subject folder
    if (dir == null) return;
    // Ask for the name + number (the next free number is suggested: first video = 001)
    final pageTitle = ((await w.getTitle()) ?? '').replaceAll(RegExp(r'\s*-\s*YouTube$'), '').trim();
    if (!mounted) return;
    final r = await askNameNumber(context,
        title: 'اسم الفيديو ورقمه',
        initialName: safeName(pageTitle),
        initialNumber: nextNumber(dir, pending: dl.pendingNumbers(dir)));
    if (r == null || !mounted) return;
    final started = dl.start(url, dir, name: r.name.isEmpty ? null : r.name, number: r.number);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(started ? 'أُضيف إلى التحميلات' : 'هذا الفيديو يُحمَّل إلى هذا المجلد بالفعل'),
      action: SnackBarAction(
        label: 'عرض',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsPage())),
      ),
    ));
  }

  @override
  Widget build(BuildContext c) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop || webFullscreen.value) return;
          if (await w.canGoBack()) {
            w.goBack();
          } else if (mounted) {
            Navigator.pop(context);
          }
        },
        child: Scaffold(
        appBar: AppBar(
          title: const Row(children: [
            Icon(Icons.smart_display, color: kAccent),
            SizedBox(width: 10),
            Text('يوتيوب'),
          ]),
          actions: [
            const DownloadsButton(),
            IconButton(
              tooltip: 'تسجيل الدخول إلى حساب Google',
              icon: const Icon(Icons.account_circle_outlined),
              onPressed: () => w.loadRequest(Uri.parse(loginUrl)),
            ),
            IconButton(tooltip: 'تحديث', icon: const Icon(Icons.refresh), onPressed: () => w.reload()),
          ],
        ),
        body: Column(children: [
          Expanded(child: FsWebView(w)),
          if (onVideo)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                Expanded(
                    child: FilledButton.icon(
                        onPressed: startStrict, icon: const Icon(Icons.lock), label: const Text('الوضع الصارم'))),
                const SizedBox(width: 8),
                Expanded(
                    child: FilledButton.tonalIcon(
                        onPressed: download, icon: const Icon(Icons.download), label: const Text('تحميل'))),
              ]),
            ),
        ]),
      ));
}

/// Strict YouTube page: locked to ONE video. Cannot open anything else.
class StrictWebPage extends StatefulWidget {
  final String url;
  final int leftMs;
  const StrictWebPage({super.key, required this.url, required this.leftMs});
  @override
  State<StrictWebPage> createState() => _StrictWebPageState();
}

class _StrictWebPageState extends State<StrictWebPage> {
  late final WebViewController w;
  late final String id = VideoId.parseVideoId(widget.url)!;
  final playing = ValueNotifier<bool>(true);
  Timer? _poll;

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
      ..setUserAgent(kChromeUA)
      ..setNavigationDelegate(NavigationDelegate(
        // Only the locked video is allowed
        onNavigationRequest: (r) => isYoutube(r.url) && r.url.contains('v=$id')
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
        onPageFinished: (_) => w.runJavaScript(lockJs),
      ))
      ..loadRequest(Uri.parse(widget.url));
    _poll = startPlayPoll(w, playing);
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) =>
      StrictShell(leftMs: widget.leftMs, playing: playing, child: FsWebView(w, strict: true));
}
