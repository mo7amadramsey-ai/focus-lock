import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'channel.dart';
import 'theme.dart';

/// Wraps any content in the strict mode:
/// - no back button, no exit button, no emergency tap
/// - the countdown is based on the REAL clock (end timestamp), so seeking
///   or pausing the video never changes it
/// - the lock is released only when the countdown reaches zero
class StrictShell extends StatefulWidget {
  final int endMillis;
  final Widget child;
  const StrictShell({super.key, required this.endMillis, required this.child});
  @override
  State<StrictShell> createState() => _StrictShellState();
}

class _StrictShellState extends State<StrictShell> {
  Timer? _t;
  Duration left = Duration.zero;
  late final int _totalMs = (widget.endMillis - DateTime.now().millisecondsSinceEpoch).clamp(1, 1 << 40).toInt();
  bool ringing = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    // Call state from native (1 = ringing)
    ch.setMethodCallHandler((call) async {
      if (call.method == 'callState' && mounted) setState(() => ringing = call.arguments == 1);
    });
    _tick();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final d = Duration(milliseconds: widget.endMillis - DateTime.now().millisecondsSinceEpoch);
    if (d <= Duration.zero) {
      _unlock();
    } else if (mounted) {
      setState(() => left = d);
    }
  }

  Future<void> _unlock() async {
    _t?.cancel();
    await ch.invokeMethod('stopLock');
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext c) {
    final progress = (1 - left.inMilliseconds / _totalMs).clamp(0.0, 1.0).toDouble();
    return PopScope(
      canPop: false, // back is blocked
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18)),
              child: Row(children: [
                // Countdown ring
                SizedBox(
                  width: 52,
                  height: 52,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 5,
                        color: kAccent,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                    const Icon(Icons.lock, size: 20, color: Colors.white70),
                  ]),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('الوضع الصارم', style: TextStyle(color: Colors.white60, fontSize: 13)),
                    Text(_fmt(left),
                        style: const TextStyle(
                            fontSize: 26, fontWeight: FontWeight.bold, fontFeatures: [FontFeature.tabularFigures()])),
                  ]),
                ),
                if (ringing)
                  IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () => ch.invokeMethod('answerCall'),
                    icon: const Icon(Icons.call),
                    tooltip: 'رد على المكالمة',
                  ),
                const SizedBox(width: 6),
                // Calling only: opens dialer / keypad / contacts
                IconButton.filledTonal(
                  onPressed: () => ch.invokeMethod('openDialer'),
                  icon: const Icon(Icons.dialpad),
                  tooltip: 'اتصال',
                ),
              ]),
            ),
            Expanded(child: widget.child),
          ]),
        ),
      ),
    );
  }
}
