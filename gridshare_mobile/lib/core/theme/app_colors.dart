import 'package:flutter/material.dart';

/// GridShare Premium Dark Palette — navy-based, role-separated accent system.
/// Rider = Electric Cyan (#00F5D4 / #00B4D8)
/// Host  = Emerald Mint (#2ECC71 / #00E676)
/// Money / Success = always Emerald Mint
class AppColors {
  // ── Base Surfaces ──────────────────────────────────────────────────────────
  static const Color background    = Color(0xFF0B0F19); // deep navy
  static const Color surface       = Color(0xFF161F30); // card background
  static const Color surfaceHigh   = Color(0xFF1E2A40); // elevated card
  static const Color surfaceOverlay= Color(0xFF0D1421); // modal scrim

  // ── Rider Theme: Electric Cyan ─────────────────────────────────────────────
  static const Color accent        = Color(0xFF00F5D4); // primary rider cyan
  static const Color accentBlue    = Color(0xFF00B4D8); // secondary rider blue
  static const Color accentSoft    = Color(0x1A00F5D4); // 10% cyan glow fill

  // ── Host Theme: Emerald Mint (money / success) ─────────────────────────────
  static const Color hostAccent    = Color(0xFF2ECC71); // host / earnings green
  static const Color hostAccentAlt = Color(0xFF00E676); // bright host alt
  static const Color hostAccentSoft= Color(0x1A2ECC71); // 10% green glow fill

  // ── Alias kept for backward compat with widgets not yet role-aware ─────────
  static const Color accentAlt     = accentBlue;

  // ── Text ───────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFFFFFFFF); // pure white headers
  static const Color textSecondary = Color(0xFF8A99AD); // muted slate labels
  static const Color textMuted     = Color(0xFF56657A); // very dim hints

  // ── Status ─────────────────────────────────────────────────────────────────
  static const Color danger        = Color(0xFFFF4D5E);
  static const Color dangerSoft    = Color(0x1FFF4D5E);
  static const Color warning       = Color(0xFFFFB23D);
  static const Color success       = Color(0xFF2ECC71); // = hostAccent

  // ── Borders / Dividers ─────────────────────────────────────────────────────
  static const Color border        = Color(0xFF243048);
  static const Color borderStrong  = Color(0xFF2E3E58);

  // ── Gradients ──────────────────────────────────────────────────────────────
  static const LinearGradient accentGlow = LinearGradient(
    colors: [Color(0xFF00F5D4), Color(0xFF00B4D8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient hostGlow = LinearGradient(
    colors: [Color(0xFF2ECC71), Color(0xFF00E676)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [Color(0xFF161F30), Color(0xFF0B0F19)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
