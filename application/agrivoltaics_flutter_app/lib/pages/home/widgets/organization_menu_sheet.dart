import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../app_constants.dart';
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
    final user = FirebaseAuth.instance.currentUser;
    final canCreateOrganization = AppConstants.canCreateOrganizationForUser(
      uid: user?.uid,
      email: user?.email,
    );
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final sheetHeight = mediaQuery.size.height * (isLandscape ? 0.94 : 0.72);

    return SafeArea(
      top: false,
      child: SizedBox(
        height: sheetHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
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
              const Expanded(
                child: OrganizationList(),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: canCreateOrganization
                        ? () {
                            Navigator.pop(context); // Close the menu first
                            showDialog(
                              context: context,
                              builder: (context) => const CreateOrganizationDialog(),
                            );
                          }
                        : null,
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
        ),
      ),
    );
  }
}
