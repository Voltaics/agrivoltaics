import 'package:flutter/material.dart';
import '../../../app_state.dart';
import '../../../models/organization.dart';
import '../../../services/organization_service.dart';
import '../../../pages/edit_organization_dialog.dart';
import 'package:provider/provider.dart';

/// Organization List Widget
/// 
/// Displays a scrollable list of all user organizations with options to:
/// - Select/switch to an organization
/// - Edit organization details
/// - Shows checkmark for currently selected organization
class OrganizationList extends StatelessWidget {
  const OrganizationList({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final currentOrg = appState.selectedOrganization;

    return StreamBuilder<List<Organization>>(
      stream: OrganizationService().getUserOrganizations(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}'),
          );
        }

        final organizations = snapshot.data ?? [];

        if (organizations.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('No organizations found'),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          itemCount: organizations.length,
          itemBuilder: (context, index) {
            final org = organizations[index];
            final isSelected = currentOrg?.id == org.id;

            return ListTile(
              leading: CircleAvatar(
                backgroundImage: org.logoUrl != null
                    ? NetworkImage(org.logoUrl!)
                    : null,
                child: org.logoUrl == null
                    ? Text(
                        org.name.isNotEmpty ? org.name[0].toUpperCase() : '?',
                      )
                    : null,
              ),
              title: Text(
                org.name,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              subtitle: org.description.isNotEmpty ? Text(org.description) : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSelected)
                    const Icon(Icons.check_circle, color: Color(0xFF2D53DA)),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () {
                      Navigator.pop(context); // Close the menu
                      showDialog(
                        context: context,
                        builder: (context) => EditOrganizationDialog(
                          organization: org,
                        ),
                      );
                    },
                    tooltip: 'Edit organization',
                  ),
                ],
              ),
              onTap: () {
                appState.setSelectedOrganization(org);
                Navigator.pop(context);
              },
            );
          },
        );
      },
    );
  }
}
