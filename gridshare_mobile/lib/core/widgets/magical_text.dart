import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../theme/app_colors.dart';

/// Gradient text with an optional shimmer sweep for magical headers.
/// Falls back gracefully — it's just a shader on a Text, no build risk.
class GradientText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final List<Color> colors;
  final bool shimmer;

  const GradientText(
    this.text, {
    super.key,
    required this.style,
    this.colors = const [AppColors.accent, AppColors.accentAlt],
    this.shimmer = true,
  });

  @override
  State<GradientText> createState() => _GradientTextState();
}

class _GradientTextState extends State<GradientText> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseGradient = LinearGradient(
      colors: widget.colors,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    if (!widget.shimmer) {
      return ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (b) => baseGradient.createShader(b),
        child: Text(widget.text, style: widget.style),
      );
    }

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        // Sweep a bright band across the text.
        final shimmer = LinearGradient(
          colors: [
            widget.colors.last,
            widget.colors.first,
            Colors.white.withValues(alpha: 0.85),
            widget.colors.first,
            widget.colors.last,
          ],
          stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
          begin: Alignment(-1.0 + 2.0 * _ctrl.value, 0),
          end: Alignment(0.0 + 2.0 * _ctrl.value, 0),
        );
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (b) => shimmer.createShader(b),
          child: Text(widget.text, style: widget.style),
        );
      },
    );
  }
}

/// A soft breathing halo behind a child — used for icons, the scan FAB, avatars.
class PulseGlow extends StatefulWidget {
  final Widget child;
  final Color color;
  final double minBlur;
  final double maxBlur;
  final double spread;

  const PulseGlow({
    super.key,
    required this.child,
    this.color = AppColors.accent,
    this.minBlur = 10,
    this.maxBlur = 26,
    this.spread = 0,
  });

  @override
  State<PulseGlow> createState() => _PulseGlowState();
}

class _PulseGlowState extends State<PulseGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final blur = widget.minBlur + (widget.maxBlur - widget.minBlur) * _ctrl.value;
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.55),
                blurRadius: blur,
                spreadRadius: widget.spread,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// A slow-rotating conic accent ring — wraps an icon/avatar with a magical halo.
class OrbitingRing extends StatefulWidget {
  final Widget child;
  final double size;
  final List<Color> colors;
  final Duration period;

  const OrbitingRing({
    super.key,
    required this.child,
    this.size = 64,
    this.colors = const [AppColors.accent, AppColors.accentAlt, Colors.transparent],
    this.period = const Duration(seconds: 6),
  });

  @override
  State<OrbitingRing> createState() => _OrbitingRingState();
}

class _OrbitingRingState extends State<OrbitingRing> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: widget.period)
    ..repeat();

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
            builder: (_, __) => Transform.rotate(
              angle: _ctrl.value * 2 * math.pi,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: widget.colors,
                    stops: const [0.0, 0.7, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // Mask the center so only a ring shows.
          Container(
            width: widget.size - 6,
            height: widget.size - 6,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.background,
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}
