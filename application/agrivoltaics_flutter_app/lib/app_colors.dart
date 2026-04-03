import 'package:flutter/material.dart';

/// Single source of truth for all app colors.
///
/// The app uses a dark-navy design language introduced on the login page and
/// carried throughout:  deep navy backgrounds, gradient sidebars, white/steel
/// text on dark surfaces, and a "light card" panel for focussed content areas.
abstract class AppColors {
  // ── Hero / page background ───────────────────────────────────────────
  static const Color background            = Color(0xFF0F1523); // deep architectural navy
  static const Color backgroundGradientEnd = Color(0xFF1A2540); // mid navy

  // ── Brand ────────────────────────────────────────────────────────────
  static const Color primary      = Color(0xFF2D53DA); // brand blue
  static const Color primaryLight = Color(0xFF5B8AF0); // lighter blue

  // ── Sidebar gradient ─────────────────────────────────────────────────
  static const Color sidebarStart = Color(0xFF2D53DA);
  static const Color sidebarEnd   = Color(0xFF1B2A99);

  // ── Agricultural accents ─────────────────────────────────────────────
  static const Color farmGreen = Color(0xFF4CAF50);
  static const Color amber     = Color(0xFFFFC107); // warm harvest accent

  // ── Semantic status ───────────────────────────────────────────────────
  static const Color error       = Color(0xFFE53935);
  static const Color errorLight  = Color(0xFFFFEBEE); // error banner background
  static const Color errorBorder = Color(0xFFEF9A9A); // error banner border
  static const Color errorDark   = Color(0xFFD32F2F); // error icon / strong emphasis
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color info      = Color(0xFF2196F3);
  static const Color infoLight = Color(0xFFE3F2FD); // pastel blue — info container bg

  // ── Text ─────────────────────────────────────────────────────────────
  /// White — primary text on dark/navy backgrounds.
  static const Color textPrimary   = Color(0xFFFFFFFF);
  /// Steel-blue white — secondary / caption text on dark backgrounds.
  static const Color textSecondary = Color(0xFFB0C0D8);
  /// Grey — body text on light (white) card surfaces.
  static const Color textMuted     = Color(0xFF6B7280);
  /// Deep navy — heading text on white card surfaces.
  static const Color textOnLight   = Color(0xFF0F1523);

  // ── Surfaces ─────────────────────────────────────────────────────────
  /// Pure white — light card panels and bottom sheets.
  static const Color surface            = Color(0xFFFFFFFF);
  /// Elevated dark card — cards / tiles on top of the navy background.
  static const Color cardDark           = Color(0xFF1E2D47);
  /// Very light blue — interior scaffold background (light-theme pages).
  static const Color scaffoldBackground = Color(0xFFF2F5FD);

  // ── Dividers / chrome ─────────────────────────────────────────────────
  /// 38 % white — dividers and subtle lines on dark/gradient surfaces.
  static const Color dividerOnDark = Color(0x61FFFFFF); // ≈ Colors.white38
}
