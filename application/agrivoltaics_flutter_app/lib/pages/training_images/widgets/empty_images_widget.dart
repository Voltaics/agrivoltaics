import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';

/// Placeholder shown when no images are available (empty library or no filter matches).
class EmptyImagesWidget extends StatelessWidget {
  final bool hasFilters;

  const EmptyImagesWidget({super.key, required this.hasFilters});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(height: 60),
          const Icon(Icons.photo_library_outlined,
              size: 80, color: AppColors.textMuted),
          const SizedBox(height: 24),
          Text(
            hasFilters
                ? 'No images match the selected filters'
                : 'No training images yet',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            hasFilters
                ? 'Try adjusting or clearing the label filters.'
                : 'Upload images using the button above to start building your training dataset.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
