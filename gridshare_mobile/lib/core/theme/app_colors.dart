import 'package:flutter/material.dart';

/// GridShare Premium Dark Palette — navy-based, role-separated accent system.
/// Rider = Electric Cyan (#00F5D4 / #00B4D8)
/// Host  = Emerald Mint (#2ECC71 / #00E676)
/// Money / Success = always Emerald Mint
class AppColors {
  // ── Base Surfaces ──────────────────────────────────────────────────────────
  static const Color background    = Color(0xFFF8F9FA); // off-white bg
  static const Color surface       = Color(0xFFFFFFFF); // white card background
  static const Color surfaceHigh   = Color(0xFFFFFFFF); // elevated card
  static const Color surfaceOverlay= Color(0x80000000); // modal scrim (darkened)

  // ── Rider Theme: Electric Cyan / Blue (adjusted for white contrast) ────────
  static const Color accent        = Color(0xFF00B4D8); // primary rider blue
  static const Color accentBlue    = Color(0xFF0096C7); // secondary rider blue
  static const Color accentSoft    = Color(0x1A00B4D8); // 10% blue glow fill

  // ── Host Theme: Emerald Mint (money / success) ─────────────────────────────
  static const Color hostAccent    = Color(0xFF27AE60); // host / earnings green
  static const Color hostAccentAlt = Color(0xFF2ECC71); // bright host alt
  static const Color hostAccentSoft= Color(0x1A27AE60); // 10% green glow fill

  // ── Alias kept for backward compat with widgets not yet role-aware ─────────
  static const Color accentAlt     = accentBlue;

  // ── Text ───────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF1A1F2C); // dark slate text
  static const Color textSecondary = Color(0xFF56657A); // medium slate labels
  static const Color textMuted     = Color(0xFF8A99AD); // very dim hints

  // ── Status ─────────────────────────────────────────────────────────────────
  static const Color danger        = Color(0xFFE74C3C);
  static const Color dangerSoft    = Color(0x1FE74C3C);
  static const Color warning       = Color(0xFFF39C12);
  static const Color success       = Color(0xFF27AE60); // = hostAccent

  // ── Borders / Dividers ─────────────────────────────────────────────────────
  static const Color border        = Color(0xFFE2E8F0);
  static const Color borderStrong  = Color(0xFFCBD5E1);

  // ── Gradients ──────────────────────────────────────────────────────────────
  static const LinearGradient accentGlow = LinearGradient(
    colors: [Color(0xFF00B4D8), Color(0xFF0096C7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient hostGlow = LinearGradient(
    colors: [Color(0xFF2ECC71), Color(0xFF27AE60)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFF8F9FA)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
