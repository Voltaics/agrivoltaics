import 'package:flutter/material.dart';
import '../../../app_state.dart';
import 'organization_menu_sheet.dart';
import 'package:provider/provider.dart';

/// Organization Selector Widget
/// 
/// A button-like widget that displays the currently selected organization
/// and allows switching to a different organization via the menu sheet.
/// Shows organization logo, name, and dropdown indicator.
class OrganizationSelector extends StatelessWidget {
  const OrganizationSelector({super.key});

  void _showOrganizationMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => const OrganizationMenuSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final currentOrg = appState.selectedOrganization;

    return InkWell(
      onTap: () => _showOrganizationMenu(context),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha((0.1 * 255).toInt()),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withAlpha((0.3 * 255).toInt()),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white.withAlpha((0.2 * 255).toInt()),
              backgroundImage: currentOrg?.logoUrl != null
                  ? NetworkImage(currentOrg!.logoUrl!)
                  : null,
              child: currentOrg?.logoUrl == null
                  ? Text(
                      currentOrg?.name.isNotEmpty == true
                          ? currentOrg!.name[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentOrg?.name ?? 'No Organization',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Switch organization',
                    style: TextStyle(
                      color: Colors.white.withAlpha((0.7 * 255).toInt()),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              color: Colors.white.withAlpha((0.7 * 255).toInt()),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
