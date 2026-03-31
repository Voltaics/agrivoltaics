import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';

/// Widget displayed when no sensor readings are available
class EmptyStateWidget extends StatelessWidget {
  const EmptyStateWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedHeight = constraints.maxHeight.isFinite;
        final isShortHeight = hasBoundedHeight && constraints.maxHeight < 520;

        final content = Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.sensors_off,
                size: isShortHeight ? 64 : 80,
                color: AppColors.textMuted,
              ),
              SizedBox(height: isShortHeight ? 16 : 24),
              const Text(
                'No sensor readings for the site/zone selected',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Select another site/zone or you can add/configure sensors and readings by clicking the options button above',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        );

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isShortHeight ? 20 : 40,
            vertical: isShortHeight ? 20 : 32,
          ),
          child: hasBoundedHeight
              ? ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: content,
                )
              : content,
        );
      },
    );
  }
}
