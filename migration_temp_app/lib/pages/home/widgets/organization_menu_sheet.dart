import 'package:flutter/material.dart';
import '../../../pages/create_organization_dialog.dart';
import 'organization_list.dart';

/// Organization Menu Bottom Sheet
/// 
/// A bottom sheet that displays the organization list, allows switching organizations,
/// and provides a button to create a new organization.
class OrganizationMenuSheet extends StatelessWidget {
  const OrganizationMenuSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text(
                  'Switch Organization',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(),
          const Flexible(
            child: OrganizationList(),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context); // Close the menu first
                  showDialog(
                    context: context,
                    builder: (context) => const CreateOrganizationDialog(),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('Create New Organization'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
