import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Circular progress ring that fills as ₹ spend approaches the prepaid cap.
/// The accent arc breathes (glow pulses) and is ringed by slowly rotating tick
/// marks for a "live instrument" feel. Driven by `progress` (0..1).
class ChargingRing extends StatefulWidget {
  final double progress;
  final double size;
  final Widget? center;

  const ChargingRing({
    super.key,
    required this.progress,
    this.size = 260,
    this.center,
  });

  @override
  State<ChargingRing> createState() => _ChargingRingState();
}

class _ChargingRingState extends State<ChargingRing> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _RingPainter(
                widget.progress.clamp(0.0, 1.0),
                _ctrl.value,
              ),
            ),
          ),
          if (widget.center != null) widget.center!,
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final double t; // 0..1 animation phase
  _RingPainter(this.progress, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final radius = size.width / 2 - 14;
    const start = -pi / 2;
    const sweep = 2 * pi;
    final breath = 0.5 + 0.5 * sin(t * 2 * pi); // 0..1 breathing

    // Track
    final track = Paint()
      ..color = AppColors.surfaceHigh
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: c, radius: radius), start, sweep, false, track);

    // Glow under active arc — pulses with the breathing phase.
    final glow = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.18 + 0.18 * breath)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22 + 6 * breath
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawArc(Rect.fromCircle(center: c, radius: radius), start, sweep * progress, false, glow);

    // Active arc (accent gradient).
    final active = Paint()
      ..shader = const LinearGradient(
        colors: [AppColors.accent, AppColors.accentAlt],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromCircle(center: c, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: c, radius: radius), start, sweep * progress, false, active);

    // Rotating tick marks around the outside — "instrument" detail.
    final ticks = Paint()
      ..color = AppColors.borderStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final tickR = radius + 12;
    final rotation = t * 2 * pi * 0.5;
    for (var i = 0; i < 48; i++) {
      final a = rotation + (i / 48) * sweep;
      final inner = tickR;
      final outer = tickR + (i % 4 == 0 ? 8 : 4);
      canvas.drawLine(
        c + Offset(cos(a), sin(a)) * inner,
        c + Offset(cos(a), sin(a)) * outer,
        ticks,
      );
    }

    // Leading dot
    if (progress > 0.001 && progress < 0.999) {
      final angle = start + sweep * progress;
      final dot = c + Offset(cos(angle), sin(angle)) * radius;
      canvas.drawCircle(dot, 16 + 4 * breath, Paint()..color = AppColors.accent.withValues(alpha: 0.25));
      canvas.drawCircle(dot, 9, Paint()..color = AppColors.accent);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.t != t;
}
