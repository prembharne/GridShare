import 'package:flutter/material.dart';
import 'app_colors.dart';

/// 4px base grid spacing + consistent corner radii.
/// Mismatched radii is the #2 "unpolished UI" tell — keep every card/button/sheet on this scale.
class AppSpacing {
  // Spacing (4px base grid)
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  // Radii — consistent across cards, buttons, bottom sheets.
  static const double rSm = 12;
  static const double rMd = 16;
  static const double rLg = 20;
  static const double rXl = 28;
  static const double rPill = 999;

  // Elevation — soft, ACCENT-tinted glow instead of default Material black shadow.
  static List<BoxShadow> glow({Color color = AppColors.accent, double strength = 0.18}) {
    return [
      BoxShadow(
        color: color.withValues(alpha:strength),
        blurRadius: 24,
        spreadRadius: -4,
        offset: const Offset(0, 8),
      ),
    ];
  }

  static List<BoxShadow> glowSoft({Color color = AppColors.accent}) => glow(color: color, strength: 0.10);
}
