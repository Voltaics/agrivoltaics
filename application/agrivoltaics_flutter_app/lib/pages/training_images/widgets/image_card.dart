import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';

import '../../../models/training_image.dart';
import '../../../services/image_service.dart';
import '../dialogs/image_detail_dialog.dart';
import 'label_badge.dart';

/// A card that shows a training image thumbnail, file name, and label badges.
/// Tapping it opens [ImageDetailDialog].
class ImageCard extends StatelessWidget {
  final TrainingImage image;
  final String orgId;
  final ImageService imageService;

  const ImageCard({
    super.key,
    required this.image,
    required this.orgId,
    required this.imageService,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 2,
      child: InkWell(
        onTap: () => _showDetail(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thumbnail
            Expanded(
              child: image.downloadUrl != null
                  ? Image.network(
                      image.downloadUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            // Labels + file name
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    image.fileName,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  if (image.labels.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: image.labels
                          .take(3)
                          .map((l) => LabelBadge(label: l))
                          .toList(),
                    ),
                    if (image.labels.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '+${image.labels.length - 3} more',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.scaffoldBackground,
      child: const Center(
        child: Icon(Icons.image, size: 40, color: AppColors.textMuted),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => ImageDetailDialog(
        image: image,
        orgId: orgId,
        imageService: imageService,
      ),
    );
  }
}
