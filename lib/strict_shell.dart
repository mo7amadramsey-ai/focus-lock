import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'channel.dart';

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
  Widget build(BuildContext c) => PopScope(
        canPop: false, // back is blocked
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('الوضع الصارم - المتبقي ${_fmt(left)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 18)),
              ),
              // Emergency calling only: opens dialer / keypad / contacts
              TextButton.icon(
                onPressed: () => ch.invokeMethod('openDialer'),
                icon: const Icon(Icons.dialpad),
                label: const Text('اتصال'),
              ),
              if (ringing)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: () => ch.invokeMethod('answerCall'),
                  icon: const Icon(Icons.call),
                  label: const Text('رد على المكالمة'),
                ),
              Expanded(child: widget.child),
            ]),
          ),
        ),
      );
}
