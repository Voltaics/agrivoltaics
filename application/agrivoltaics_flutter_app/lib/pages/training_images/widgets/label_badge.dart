import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';

/// A small coloured badge used to display a single image label.
class LabelBadge extends StatelessWidget {
  final String label;

  const LabelBadge({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary.withAlpha((0.12 * 255).toInt()),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
