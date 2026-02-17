import 'package:flutter/material.dart';

/// Single source of truth for all app colors.
abstract class AppColors {
  // ── Hero / Login background ──────────────────────────────────────────
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

  // ── Semantic ─────────────────────────────────────────────────────────
  static const Color error = Color(0xFFE53935);

  // ── Text ─────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0C0D8); // muted steel-blue white

  // ── Surfaces ─────────────────────────────────────────────────────────
  static const Color surface            = Color(0xFFFFFFFF);
  static const Color scaffoldBackground = Color(0xFFF2F5FD); // interior page bg
}
