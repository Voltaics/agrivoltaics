import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:agrivoltaics_flutter_app/app_constants.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/organization_service.dart';
import '../../member_directory/member_directory_page.dart';
import 'sign_out_dialog.dart';

class AppOverflowMenuButton extends StatefulWidget {
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

  @override
  State<AppOverflowMenuButton> createState() => _AppOverflowMenuButtonState();
}

class _AppOverflowMenuButtonState extends State<AppOverflowMenuButton> {
  // Defaults to hidden until the permission check resolves, so the option
  // never flashes visible for someone who isn't allowed to use it.
  bool _canAccessDirectory = false;

  @override
  void initState() {
    super.initState();
    OrganizationService().canManageMembersInAnyOrg().then((canAccess) {
      if (mounted) setState(() => _canAccessDirectory = canAccess);
    });
  }

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
      case 'directory':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const MemberDirectoryPage()),
        );
        break;
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
      tooltip: widget.tooltip,
      padding: widget.padding,
      icon: Icon(
        Icons.menu,
        color: widget.iconColor,
        size: widget.iconSize,
      ),
      onSelected: (value) => _handleSelection(context, value),
      itemBuilder: (context) => [
        if (_canAccessDirectory)
          const PopupMenuItem<String>(
            value: 'directory',
            child: Row(
              children: [
                Icon(Icons.people_outline),
                SizedBox(width: 12),
                Text('Member Directory'),
              ],
            ),
          ),
        const PopupMenuItem<String>(
          value: 'help',
          child: Row(
            children: [
              Icon(Icons.help_outline),
              SizedBox(width: 12),
              Text('Help'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
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