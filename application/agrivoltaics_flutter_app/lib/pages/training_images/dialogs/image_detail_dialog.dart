import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/training_image.dart';
import '../../../services/image_service.dart';
import '../widgets/label_badge.dart';

/// Dialog that displays full image details and allows the user to delete it.
class ImageDetailDialog extends StatelessWidget {
  final TrainingImage image;
  final String orgId;
  final ImageService imageService;

  const ImageDetailDialog({
    super.key,
    required this.image,
    required this.orgId,
    required this.imageService,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image
            Flexible(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                child: image.downloadUrl != null
                    ? Image.network(image.downloadUrl!, fit: BoxFit.contain)
                    : Container(
                        height: 200,
                        color: AppColors.scaffoldBackground,
                        child: const Center(
                          child: Icon(Icons.image,
                              size: 60, color: AppColors.textMuted),
                        ),
                      ),
              ),
            ),

            // Metadata
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    image.fileName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (image.labels.isNotEmpty) ...[
                    const Text(
                      'Labels',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      children: image.labels
                          .map((l) => LabelBadge(label: l))
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (image.notes != null && image.notes!.isNotEmpty) ...[
                    const Text(
                      'Notes',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(image.notes!,
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    'Uploaded ${DateFormat.yMd().format(image.uploadedAt)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),

            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    style:
                        TextButton.styleFrom(foregroundColor: AppColors.error),
                    onPressed: () async {
                      final confirmed = await _confirmDelete(context);
                      if (confirmed && context.mounted) {
                        await imageService.deleteImage(
                            orgId, image.id, image.storagePath);
                        if (context.mounted) Navigator.of(context).pop();
                      }
                    },
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete Image'),
            content: const Text(
                'Are you sure you want to permanently delete this image?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                style:
                    TextButton.styleFrom(foregroundColor: AppColors.error),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }
}
