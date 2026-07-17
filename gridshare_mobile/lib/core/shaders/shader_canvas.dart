import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../theme/app_colors.dart';

/// A spec describing one shader: its asset path and how to pack uniforms.
///
/// Uniform index order MUST match the declaration order in the .frag file.
/// Example (aurora.frag): 0,1=uResolution.xy · 2=uTime · 3,4,5=uColorA · 6,7,8=uColorB.
class ShaderSpec {
  final String asset;
  final List<double> Function(double time, Size size) pack;

  const ShaderSpec(this.asset, this.pack);

  static ShaderSpec aurora({Color? color, Color? a, Color b = AppColors.accentAlt}) {
    final primary = color ?? a ?? AppColors.accent;
    return ShaderSpec(
      'lib/core/shaders/shaders/aurora.frag',
      (t, size) => [
        size.width,
        size.height, // uResolution
        t, // uTime
        primary.r / 255,
        primary.g / 255,
        primary.b / 255, // uColorA
        b.r / 255,
        b.g / 255,
        b.b / 255, // uColorB
      ],
    );
  }

  static ShaderSpec ripple({Color color = AppColors.accent, double intensity = 0.5}) =>
      ShaderSpec(
        'lib/core/shaders/shaders/ripple.frag',
        (t, size) => [
          size.width, size.height,
          t,
          color.r / 255, color.g / 255, color.b / 255,
          intensity,
        ],
      );

  static ShaderSpec pulse({Color color = AppColors.accent, double progress = 0.0}) => ShaderSpec(
        'lib/core/shaders/shaders/pulse.frag',
        (t, size) => [
          size.width, size.height,
          t,
          color.r / 255, color.g / 255, color.b / 255,
          progress.clamp(0.0, 1.0),
        ],
      );

  /// Drifting "magical dust" particles — used as an atmospheric overlay.
  static ShaderSpec spark({Color color = AppColors.accent, double density = 0.9}) =>
      ShaderSpec(
        'lib/core/shaders/shaders/spark.frag',
        (t, size) => [
          size.width, size.height,
          t,
          color.r / 255, color.g / 255, color.b / 255,
          density,
        ],
      );
}

/// Animated shader surface. Falls back to a premium gradient if the program
/// fails to load (e.g. before `flutter pub get` resolves assets) so the app
/// never shows a blank/error surface.
class ShaderCanvas extends StatefulWidget {
  final ShaderSpec spec;
  final double speed;
  final Gradient fallback;

  const ShaderCanvas({
    super.key,
    required this.spec,
    this.speed = 1.0,
    this.fallback = AppColors.surfaceGradient,
  });

  @override
  State<ShaderCanvas> createState() => _ShaderCanvasState();
}

class _ShaderCanvasState extends State<ShaderCanvas> with SingleTickerProviderStateMixin {
  FragmentProgram? _program;
  double _time = 0;
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Ticker((elapsed) {
      if (!mounted) return;
      setState(() => _time = elapsed.inMilliseconds / 1000 * widget.speed);
    });
    _ticker.start();
  }

  Future<void> _load() async {
    try {
      final program = await FragmentProgram.fromAsset(widget.spec.asset);
      if (mounted) setState(() => _program = program);
    } catch (_) {
      // Keep _program null → fallback gradient paints instead.
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ShaderPainter(
        program: _program,
        spec: widget.spec,
        time: _time,
        fallback: widget.fallback,
      ),
      size: Size.infinite,
    );
  }
}

class _ShaderPainter extends CustomPainter {
  final FragmentProgram? program;
  final ShaderSpec spec;
  final double time;
  final Gradient fallback;

  _ShaderPainter({
    required this.program,
    required this.spec,
    required this.time,
    required this.fallback,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (program == null) {
      final paint = Paint()..shader = fallback.createShader(Offset.zero & size);
      canvas.drawRect(Offset.zero & size, paint);
      return;
    }
    final shader = program!.fragmentShader();
    final uniforms = spec.pack(time, size);
    for (var i = 0; i < uniforms.length; i++) {
      shader.setFloat(i, uniforms[i]);
    }
    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _ShaderPainter old) => true;
}
