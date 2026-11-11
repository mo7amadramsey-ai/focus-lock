import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'channel.dart';
import 'lock_setup.dart';
import 'nav.dart';
import 'theme.dart';

/// Wraps any content in the strict mode:
/// - no back button / exit while the timer runs
/// - the countdown only runs while the video is PLAYING and the app is on screen:
///   paused video, screen off or app in background = the timer stops
/// - the remaining time is saved natively, so it survives a restart / reboot
/// - the lock is never longer than one hour
/// - when time is up the content is NOT closed: it offers to extend the focus time
/// - the time can be extended at any moment (never shortened)
class StrictShell extends StatefulWidget {
  final int leftMs; // time still to be watched
  final Widget child;
  final ValueListenable<bool>? playing; // null = always counts (while the app is on screen)
  const StrictShell({super.key, required this.leftMs, required this.child, this.playing});
  @override
  State<StrictShell> createState() => _StrictShellState();
}

class _StrictShellState extends State<StrictShell> with WidgetsBindingObserver {
  Timer? _t;
  late int _leftMs = widget.leftMs.clamp(0, kMaxLockMs).toInt();
  late int _totalMs = _leftMs < 1 ? 1 : _leftMs;
  Duration get left => Duration(milliseconds: _leftMs);
  DateTime _last = DateTime.now();
  int _n = 0;
  bool _fg = true, _focus = true, counting = true;
  bool ringing = false, expired = false, sheetOpen = false, unlocked = false;
  // Same key in portrait and landscape: the video is MOVED, never rebuilt, when the phone rotates
  final _childKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    strictActive.value = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    ch.setMethodCallHandler((call) async {
      if (call.method == 'callState' && mounted) setState(() => ringing = call.arguments == 1);
    });
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  // App on screen (resumed) = counts; screen off / background / dialogs over the app = does not
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    _fg = s == AppLifecycleState.resumed;
    _last = DateTime.now();
    if (!_fg) _save();
  }

  // Remaining time is stored natively: a restart or reboot resumes with exactly what is left
  void _save() {
    if (unlocked || expired) return;
    ch.invokeMethod('setLeft', {'left': _leftMs});
  }

  void _tick() {
    final now = DateTime.now();
    final dt = now.difference(_last).inMilliseconds.clamp(0, 2000).toInt(); // long gaps never count
    _last = now;
    if (unlocked || expired || !mounted) return;
    final was = counting;
    // Counts only if: app on screen + OUR window focused and full-screen (no floating/pop-up/split window) + video playing
    ch.invokeMethod<bool>('isFocused').then((v) => _focus = v ?? true).catchError((_) => true);
    counting = _fg && _focus && (widget.playing?.value ?? true);
    if (counting) _leftMs -= dt;
    if (_leftMs <= 0) {
      _leftMs = 0;
      _expire();
      return;
    }
    setState(() {});
    _n++;
    if (_n % 3 == 0 || (was && !counting)) _save();
  }

  // Time is up: release the kiosk but KEEP the video, and offer more time
  Future<void> _expire() async {
    expired = true;
    _leftMs = 0;
    HapticFeedback.heavyImpact();
    await ch.invokeMethod('releaseLock');
    if (!mounted) return;
    setState(() {});
    _askExtend();
  }

  Future<void> _askExtend() async {
    if (sheetOpen || !mounted) return;
    sheetOpen = true;
    final r = await pickExtension(context, expired: expired);
    sheetOpen = false;
    if (r == null || !mounted) return;
    if (r == -1) {
      // continue watching with no lock at all
      await ch.invokeMethod('stopLock');
      setState(() => unlocked = true);
      return;
    }
    // never more than one hour in total
    final newLeft = ((expired ? 0 : _leftMs) + r * 60000).clamp(0, kMaxLockMs).toInt();
    if (!expired && newLeft <= _leftMs) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الحد الأقصى للقفل ساعة واحدة')));
      return;
    }
    await ch.invokeMethod('extendLock', {'left': newLeft});
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() {
      _leftMs = newLeft;
      _totalMs = newLeft < 1 ? 1 : newLeft;
      expired = false;
    });
    _last = DateTime.now();
  }

  Future<void> _finish() async {
    _t?.cancel();
    await ch.invokeMethod('stopLock');
    strictActive.value = false;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    WakelockPlus.disable();
    if (mounted) goHome(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _t?.cancel();
    strictActive.value = false;
    super.dispose();
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  List<Widget> _actions({bool small = false}) => [
        if (ringing)
          IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => ch.invokeMethod('answerCall'),
            icon: const Icon(Icons.call),
            tooltip: 'رد على المكالمة',
          ),
        if (!unlocked)
          IconButton.filledTonal(
            onPressed: _askExtend,
            icon: Icon(expired ? Icons.more_time : Icons.add_alarm),
            tooltip: 'تمديد الوقت',
          ),
        const SizedBox(width: 4),
        IconButton.filledTonal(
          onPressed: () => ch.invokeMethod('openDialer'),
          icon: const Icon(Icons.dialpad),
          tooltip: 'اتصال',
        ),
        if (expired || unlocked) ...[
          const SizedBox(width: 4),
          IconButton.filled(onPressed: _finish, icon: const Icon(Icons.close), tooltip: 'إنهاء الجلسة'),
        ],
      ];

  Widget _fullHeader(double progress) {
    final ended = expired || unlocked;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ended ? Colors.greenAccent.withOpacity(.4) : kOutline),
      ),
      child: Row(children: [
        SizedBox(
          width: 54,
          height: 54,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(
              width: 54,
              height: 54,
              child: CircularProgressIndicator(
                value: ended ? 1 : progress,
                strokeWidth: 5,
                color: ended ? Colors.greenAccent : kAccent,
                backgroundColor: Colors.white12,
              ),
            ),
            Icon(ended ? Icons.lock_open : Icons.lock, size: 20, color: Colors.white70),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              unlocked ? 'بدون قفل' : (expired ? 'انتهى وقت التركيز' : (counting ? 'الوضع الصارم' : (!_focus ? 'متوقف — أغلق النوافذ العائمة' : 'متوقف — شغّل الفيديو'))),
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
            Text(
              ended ? (unlocked ? 'أحسنت' : '00:00:00') : _fmt(left),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ]),
        ),
        ..._actions(),
      ]),
    );
  }

  Widget _compactBar() {
    final ended = expired || unlocked;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(color: Colors.black.withOpacity(.65), borderRadius: BorderRadius.circular(24)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ended ? Icons.lock_open : (counting ? Icons.lock : Icons.pause_circle), size: 16, color: ended ? Colors.greenAccent : (counting ? kAccent : Colors.orangeAccent)),
        const SizedBox(width: 6),
        Text(ended ? 'انتهى' : _fmt(left),
            style: const TextStyle(fontWeight: FontWeight.bold, fontFeatures: [FontFeature.tabularFigures()])),
        const SizedBox(width: 4),
        ..._actions(small: true).map((w) => w is IconButton
            ? IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: w.onPressed,
                icon: w.icon,
                tooltip: w.tooltip,
              )
            : w),
      ]),
    );
  }

  @override
  Widget build(BuildContext c) {
    final progress = (1 - left.inMilliseconds / _totalMs).clamp(0.0, 1.0).toDouble();
    final land = MediaQuery.orientationOf(c) == Orientation.landscape;
    final child = KeyedSubtree(key: _childKey, child: widget.child);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && (expired || unlocked)) _finish();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _guard(land
            ? Stack(children: [
                Positioned.fill(child: child),
                Positioned(top: 4, left: 8, child: SafeArea(child: _compactBar())),
              ])
            : SafeArea(
                child: Column(children: [
                  _fullHeader(progress),
                  Expanded(child: child),
                ]),
              )),
      ),
    );
  }

  // While our window is floating / unfocused the content is hidden behind a black cover
  Widget _guard(Widget w) => Stack(children: [
        Positioned.fill(child: Offstage(offstage: !_focus, child: w)),
        if (!_focus)
          const Positioned.fill(
            child: ColoredBox(
              color: Colors.black,
              child: Center(
                child: Text('أغلق النوافذ العائمة لمتابعة المشاهدة',
                    style: TextStyle(color: Colors.white70, fontSize: 18)),
              ),
            ),
          ),
      ]);
}

// ---- Play state of a <video> inside a web page (YouTube / Moodle) ----
// 0 = paused / ended / buffering, 1 = playing, 2 = no <video> in the main page (e.g. a player inside an iframe):
// then we cannot know, so the time simply counts (never leaves you stuck).
const _pollJs = "(function(){var vs=document.querySelectorAll('video');if(!vs.length)return 2;"
    "for(var i=0;i<vs.length;i++){var v=vs[i];if(!v.paused&&!v.ended&&v.readyState>2)return 1;}return 0;})()";

/// Updates [out] every second with whether the page's video is playing. Cancel the returned timer in dispose.
Timer startPlayPoll(WebViewController w, ValueNotifier<bool> out) => Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final r = await w.runJavaScriptReturningResult(_pollJs);
        out.value = (int.tryParse(r.toString().replaceAll('"', '')) ?? 2) != 0;
      } catch (_) {
        out.value = true;
      }
    });
