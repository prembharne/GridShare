import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Typography: a distinctive display face for numbers/headings + Inter for body.
/// If the custom fonts (Clash Display / General Sans / Inter) are not yet bundled,
/// Flutter falls back to the system font with a debug warning — no build break.
class AppTextStyles {
  static const String displayFamily = 'ClashDisplay';
  static const String bodyFamily = 'Inter';

  static const TextStyle display = TextStyle(
    fontFamily: displayFamily,
    fontSize: 34,
    height: 1.05,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary, // #FFFFFF
    letterSpacing: -0.5,
  );

  static const TextStyle heading = TextStyle(
    fontFamily: displayFamily,
    fontSize: 24,
    height: 1.1,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
  );

  static const TextStyle title = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 18,
    height: 1.2,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 15,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static const TextStyle label = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 12,
    height: 1.2,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary, // #8A99AD
    letterSpacing: 0.8,
  );

  /// The live ₹ counter — large, tabular, display face.
  static const TextStyle counter = TextStyle(
    fontFamily: displayFamily,
    fontSize: 56,
    height: 1.0,
    fontWeight: FontWeight.w700,
    color: AppColors.accent,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle caption = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );
}
