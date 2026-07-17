import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Surface card with 1px hairline border + optional accent glow.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final bool glow;
  final Color? glowColor;
  final VoidCallback? onTap;
  final double radius;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.glow = false,
    this.glowColor,
    this.onTap,
    this.radius = AppSpacing.rMd,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppColors.border, width: 1),
      boxShadow: glow ? AppSpacing.glow(color: glowColor ?? AppColors.accent) : null,
    );

    final content = Container(
      padding: padding,
      decoration: decoration,
      child: child,
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: content,
      ),
    );
  }
}

/// A thin accent-tinted container used behind active/charging elements.
class GlowContainer extends StatelessWidget {
  final Widget child;
  final Color color;
  final double radius;
  final EdgeInsets padding;

  const GlowContainer({
    super.key,
    required this.child,
    this.color = AppColors.accent,
    this.radius = AppSpacing.rLg,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: color.withValues(alpha:0.35), width: 1),
        boxShadow: AppSpacing.glow(color: color, strength: 0.16),
      ),
      child: child,
    );
  }
}
