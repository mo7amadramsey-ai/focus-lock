import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// Signature element of Focus Lock: a safe-dial.
///
/// 60 ticks sweep clockwise in ember→gold when the lock is armed and rest dark when it
/// is not; a soft glow breathes behind it. Tapping the dial is the app's primary action.
class FocusDial extends StatefulWidget {
  /// true = armed, false = needs setup, null = still checking.
  final bool? armed;
  final String title;
  final String caption;
  final VoidCallback onTap;

  const FocusDial({
    super.key,
    required this.armed,
    required this.title,
    required this.caption,
    required this.onTap,
  });

  @override
  State<FocusDial> createState() => _FocusDialState();
}

class _FocusDialState extends State<FocusDial> with TickerProviderStateMixin {
  late final AnimationController _sweep =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))..forward();
  late final AnimationController _breath =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);

  @override
  void didUpdateWidget(FocusDial old) {
    super.didUpdateWidget(old);
    // Re-run the "locking" sweep when the lock becomes armed
    if (old.armed != true && widget.armed == true) _sweep.forward(from: 0);
  }

  @override
  void dispose() {
    _sweep.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final armed = widget.armed == true;
    return Semantics(
      button: true,
      label: '${widget.title}. ${widget.caption}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AspectRatio(
          aspectRatio: 1,
          child: AnimatedBuilder(
            animation: Listenable.merge([_sweep, _breath]),
            builder: (_, __) => CustomPaint(
              painter: _DialPainter(
                sweep: Curves.easeOutCubic.transform(_sweep.value),
                breath: _breath.value,
                armed: armed,
              ),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    armed ? Icons.lock_rounded : Icons.lock_open_rounded,
                    size: 40,
                    color: armed ? kGold : kTextDim,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kText),
                  ),
                  if (widget.caption.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.caption,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: kTextDim),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  final double sweep;
  final double breath;
  final bool armed;
  const _DialPainter({required this.sweep, required this.breath, required this.armed});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    // Breathing glow (only when armed)
    if (armed) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [kAccent.withOpacity(.20 + .10 * breath), kAccent.withOpacity(0)],
            stops: const [.45, 1],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    // Inner disc
    canvas.drawCircle(c, r * .64, Paint()..color = kSurface);
    canvas.drawCircle(
      c,
      r * .64,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = kOutline,
    );

    // 60 ticks, every fifth one is a major mark
    const n = 60;
    final lit = armed ? (sweep * n).floor() : -1;
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / n;
      final major = i % 5 == 0;
      final r1 = r * (major ? .79 : .84);
      final r2 = r * .93;
      final on = i <= lit;
      final Color col = on
          ? Color.lerp(kGold, kAccent, i / n)!
          : (major ? kOutline : kOutline.withOpacity(.65));
      canvas.drawLine(
        c + Offset(math.cos(a) * r1, math.sin(a) * r1),
        c + Offset(math.cos(a) * r2, math.sin(a) * r2),
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = major ? 3.4 : 1.9
          ..color = col,
      );
    }

    // Pointer at 12 o'clock
    final tip = Path()
      ..moveTo(c.dx - 6, c.dy - r * .995)
      ..lineTo(c.dx + 6, c.dy - r * .995)
      ..lineTo(c.dx, c.dy - r * .94)
      ..close();
    canvas.drawPath(tip, Paint()..color = armed ? kGold : kTextDim);
  }

  @override
  bool shouldRepaint(_DialPainter o) => o.sweep != sweep || o.breath != breath || o.armed != armed;
}
