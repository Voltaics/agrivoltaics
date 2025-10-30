import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/organization.dart';
import '../services/organization_service.dart';
import '../app_state.dart';
import 'home/home.dart';
import 'create_organization_dialog.dart';

class OrganizationSelectionPage extends StatefulWidget {
  const OrganizationSelectionPage({super.key});

  @override
  State<OrganizationSelectionPage> createState() => _OrganizationSelectionPageState();
}

class _OrganizationSelectionPageState extends State<OrganizationSelectionPage> {
  final OrganizationService _orgService = OrganizationService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Organization'),
        automaticallyImplyLeading: false, // Remove back button
      ),
      body: StreamBuilder<List<Organization>>(
        stream: _orgService.getUserOrganizations(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Error loading organizations: ${snapshot.error}'),
            );
          }

          final organizations = snapshot.data ?? [];

          if (organizations.isEmpty) {
            return _buildNoOrganizationsView();
          }

          return _buildOrganizationList(organizations);
        },
      ),
    );
  }

  Widget _buildNoOrganizationsView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.business_outlined,
              size: 80,
              color: Colors.grey,
            ),
            const SizedBox(height: 24),
            const Text(
              'No Organizations',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'You are not currently in any organizations. You can create your own or contact members from the organization you need to join.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => const CreateOrganizationDialog(),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Create Organization'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrganizationList(List<Organization> organizations) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Select an organization to continue',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: organizations.length,
            itemBuilder: (context, index) {
              final org = organizations[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    radius: 30,
                    backgroundImage: org.logoUrl != null
                        ? NetworkImage(org.logoUrl!)
                        : null,
                    child: org.logoUrl == null
                        ? Text(
                            org.name.isNotEmpty ? org.name[0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 24),
                          )
                        : null,
                  ),
                  title: Text(
                    org.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: org.description.isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(org.description),
                        )
                      : null,
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () => _selectOrganization(org),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: OutlinedButton.icon(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const CreateOrganizationDialog(),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Create New Organization'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  void _selectOrganization(Organization org) {
    // Store the selected organization in app state
    final appState = Provider.of<AppState>(context, listen: false);
    appState.setSelectedOrganization(org);

    // Navigate to home
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const HomeState(),
      ),
    );
  }
}
