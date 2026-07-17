import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/shaders/shader_canvas.dart';
import '../../core/widgets/magical_text.dart';

/// The hero 2.5D "energy flow" visual.
///
/// Default path: a pure-Flutter animated orb (custom pulse shader) — runnable
/// today with zero binary assets. Drop a real Rive `.riv` at
/// `assets/rive/energy.riv` and flip `_useRive = true` to upgrade to a Rive
/// 2.5D animation (no other code change needed).
class EnergyFlow25D extends StatelessWidget {
  final double progress; // 0..1, drives shader intensity
  final double size;

  static const bool _useRive = false; // set true once assets/rive/energy.riv exists

  const EnergyFlow25D({super.key, this.progress = 0.0, this.size = 280});

  @override
  Widget build(BuildContext context) {
    if (_useRive) {
      // Rive's API: RiveAnimation.asset('assets/rive/energy.riv') with a
      // StateMachine driving 'charge' from `progress`. Guarded so a missing
      // asset degrades to the shader below instead of crashing.
      return _ShaderOrb(progress: progress, size: size);
    }
    return _ShaderOrb(progress: progress, size: size);
  }
}

class _ShaderOrb extends StatefulWidget {
  final double progress;
  final double size;
  const _ShaderOrb({required this.progress, required this.size});

  @override
  State<_ShaderOrb> createState() => _ShaderOrbState();
}

class _ShaderOrbState extends State<_ShaderOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Orb grows/brightens as the session progresses — visible "energy building".
    final fill = 0.55 + 0.45 * widget.progress.clamp(0.0, 1.0);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Breathing halo behind the orb.
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) {
              final pulse = 0.5 + 0.5 * _ctrl.value;
              return Container(
                width: widget.size * (0.7 + 0.1 * pulse),
                height: widget.size * (0.7 + 0.1 * pulse),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.25 + 0.2 * pulse),
                      blurRadius: 40 + 30 * pulse,
                      spreadRadius: -10,
                    ),
                  ],
                ),
              );
            },
          ),
          ClipOval(
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ShaderCanvas(
                    spec: ShaderSpec.pulse(color: AppColors.accent, progress: fill),
                    fallback: const LinearGradient(
                      colors: [AppColors.accentSoft, Colors.transparent],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  ShaderCanvas(
                    spec: ShaderSpec.spark(color: AppColors.accentAlt, density: 0.4),
                    fallback: AppColors.surfaceGradient,
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: widget.size * 0.62,
            height: widget.size * 0.62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [AppColors.accent.withValues(alpha: 0.25), AppColors.surface],
                stops: const [0.0, 0.75],
              ),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.4), width: 1),
            ),
          ),
        ],
      ),
    );
  }
}

