import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:agrivoltaics_flutter_app/app_constants.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'sign_out_dialog.dart';

class AppOverflowMenuButton extends StatelessWidget {
  final Color iconColor;
  final EdgeInsetsGeometry padding;
  final String tooltip;
  final double? iconSize;

  const AppOverflowMenuButton({
    super.key,
    this.iconColor = AppColors.textPrimary,
    this.padding = const EdgeInsets.all(8),
    this.tooltip = 'Menu',
    this.iconSize,
  });

  Future<void> _openHelpPdf(BuildContext context) async {
    final uri = Uri.parse(AppConstants.helpPdfUrl);

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open help PDF.'),
        ),
      );
    }
  }

  Future<void> _handleSelection(BuildContext context, String value) async {
    switch (value) {
      case 'help':
        await _openHelpPdf(context);
        break;
      case 'logout':
        if (!context.mounted) return;
        showDialog(
          context: context,
          builder: (BuildContext context) => const SignOutDialog(),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: tooltip,
      padding: padding,
      icon: Icon(
        Icons.menu,
        color: iconColor,
        size: iconSize,
      ),
      onSelected: (value) => _handleSelection(context, value),
      itemBuilder: (context) => const [
        PopupMenuItem<String>(
          value: 'help',
          child: Row(
            children: [
              Icon(Icons.help_outline),
              SizedBox(width: 12),
              Text('Help'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout),
              SizedBox(width: 12),
              Text('Logout'),
            ],
          ),
        ),
      ],
    );
  }
}