import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Frosted-glass surface — the "premium" material. A translucent fill + hairline
/// border + TINTED glow reads as depth without a drop shadow. Used for cards,
/// sheets, and the payment hero.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final bool glow;
  final Color? glowColor;
  final VoidCallback? onTap;
  final double radius;
  final double blur;
  final Color tint;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.glow = false,
    this.glowColor,
    this.onTap,
    this.radius = AppSpacing.rMd,
    this.blur = 18,
    this.tint = AppColors.surface,
  });

  @override
  Widget build(BuildContext context) {
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: (glow ? (glowColor ?? AppColors.accent) : AppColors.border)
                  .withValues(alpha: glow ? 0.45 : 0.6),
              width: 1,
            ),
            boxShadow: glow
                ? AppSpacing.glow(color: glowColor ?? AppColors.accent, strength: 0.16)
                : null,
          ),
          child: child,
        ),
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        splashColor: (glowColor ?? AppColors.accent).withValues(alpha: 0.12),
        highlightColor: (glowColor ?? AppColors.accent).withValues(alpha: 0.08),
        child: content,
      ),
    );
  }
}
