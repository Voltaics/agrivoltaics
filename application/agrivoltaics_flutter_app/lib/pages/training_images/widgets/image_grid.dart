import 'package:flutter/material.dart';

import '../../../models/training_image.dart';
import '../../../services/image_service.dart';
import 'image_card.dart';

/// A responsive grid of [ImageCard] widgets.
/// 4 columns on wide screens (≥ 900 px), 2 columns on narrow screens.
class ImageGrid extends StatelessWidget {
  final List<TrainingImage> images;
  final String orgId;
  final ImageService imageService;

  const ImageGrid({
    super.key,
    required this.images,
    required this.orgId,
    required this.imageService,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    final crossAxisCount = isWide ? 4 : 2;

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: images.length,
      itemBuilder: (context, i) {
        return ImageCard(
          image: images[i],
          orgId: orgId,
          imageService: imageService,
        );
      },
    );
  }
}
