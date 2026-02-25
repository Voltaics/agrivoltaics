import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';

/// Placeholder shown when no organization is selected.
class NoOrgWidget extends StatelessWidget {
  const NoOrgWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(height: 60),
          Icon(Icons.photo_library_outlined,
              size: 80, color: AppColors.textMuted),
          SizedBox(height: 24),
          Text(
            'No organization selected',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Select an organization from the sidebar to view and upload training images.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
