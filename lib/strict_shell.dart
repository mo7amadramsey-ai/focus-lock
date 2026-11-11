import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'channel.dart';
import 'lock_setup.dart';
import 'nav.dart';
import 'theme.dart';

/// Wraps any content in the strict mode:
/// - no back button / exit while the timer runs
/// - the countdown uses the REAL clock, so seeking or pausing never changes it
/// - when time is up the content is NOT closed: it offers to extend the focus time
/// - the time can be extended at any moment (never shortened)
class StrictShell extends StatefulWidget {
  final int endMillis;
  final Widget child;
  const StrictShell({super.key, required this.endMillis, required this.child});
  @override
  State<StrictShell> createState() => _StrictShellState();
}

class _StrictShellState extends State<StrictShell> {
  Timer? _t;
  late int end = widget.endMillis;
  late int _totalMs = (end - DateTime.now().millisecondsSinceEpoch).clamp(1, 1 << 40).toInt();
  Duration left = Duration.zero;
  // Same key in portrait and landscape: the video is MOVED, never rebuilt, when the phone rotates
  final _childKey = GlobalKey();
  bool ringing = false, expired = false, sheetOpen = false, unlocked = false;

  @override
  void initState() {
    super.initState();
    strictActive.value = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    ch.setMethodCallHandler((call) async {
      if (call.method == 'callState' && mounted) setState(() => ringing = call.arguments == 1);
    });
    _tick();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (unlocked || !mounted) return;
    final d = Duration(milliseconds: end - DateTime.now().millisecondsSinceEpoch);
    if (d <= Duration.zero) {
      if (!expired) {
        _expire();
      }
    } else {
      setState(() => left = d);
    }
  }

  // Time is up: release the kiosk but KEEP the video, and offer more time
  Future<void> _expire() async {
    expired = true;
    left = Duration.zero;
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
    final now = DateTime.now().millisecondsSinceEpoch;
    final newEnd = (expired ? now : end) + r * 60000;
    await ch.invokeMethod('extendLock', {'end': newEnd});
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() {
      end = newEnd;
      _totalMs = (newEnd - now).clamp(1, 1 << 40).toInt();
      expired = false;
    });
    _tick();
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
              unlocked ? 'بدون قفل' : (expired ? 'انتهى وقت التركيز' : 'الوضع الصارم'),
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
        Icon(ended ? Icons.lock_open : Icons.lock, size: 16, color: ended ? Colors.greenAccent : kAccent),
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
        body: land
            ? Stack(children: [
                Positioned.fill(child: child),
                Positioned(top: 4, left: 8, child: SafeArea(child: _compactBar())),
              ])
            : SafeArea(
                child: Column(children: [
                  _fullHeader(progress),
                  Expanded(child: child),
                ]),
              ),
      ),
    );
  }
}
