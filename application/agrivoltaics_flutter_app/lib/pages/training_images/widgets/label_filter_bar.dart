import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';

/// A horizontal filter bar that displays all available image labels as
/// [FilterChip]s and an AND / OR mode toggle.
class LabelFilterBar extends StatelessWidget {
  final List<String> availableLabels;
  final List<String> selectedLabels;

  /// When `true` all selected labels must be present (AND);
  /// when `false` any selected label is sufficient (OR).
  final bool filterModeAnd;

  final void Function(String label) onToggleLabel;
  final VoidCallback onToggleMode;
  final VoidCallback onClear;

  const LabelFilterBar({
    super.key,
    required this.availableLabels,
    required this.selectedLabels,
    required this.filterModeAnd,
    required this.onToggleLabel,
    required this.onToggleMode,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AND/OR toggle + clear button
          Row(
            children: [
              const Text(
                'Filter by label:',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 12),
              // AND / OR toggle
              GestureDetector(
                onTap: onToggleMode,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha((0.12 * 255).toInt()),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.primary.withAlpha((0.4 * 255).toInt()),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        filterModeAnd ? 'AND' : 'OR',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.swap_horiz,
                          size: 14, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (selectedLabels.isNotEmpty)
                TextButton(
                  onPressed: onClear,
                  child: const Text('Clear filters',
                      style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Label chips
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: availableLabels.map((label) {
              final selected = selectedLabels.contains(label);
              return FilterChip(
                label: Text(label, style: const TextStyle(fontSize: 12)),
                selected: selected,
                onSelected: (_) => onToggleLabel(label),
                selectedColor:
                    AppColors.primary.withAlpha((0.2 * 255).toInt()),
                checkmarkColor: AppColors.primary,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
