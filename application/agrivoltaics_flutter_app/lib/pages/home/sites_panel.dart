import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart' hide Site;
import '../../models/site.dart';
import '../../services/site_service.dart';
import '../create_site_dialog.dart';

class SitesPanel extends StatelessWidget {
  const SitesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final selectedOrg = appState.selectedOrganization;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isWideScreen = screenWidth >= 1280 || screenHeight < screenWidth;

    if (selectedOrg == null) {
      return const Center(
        child: Text('No organization selected'),
      );
    }

    // For wide screens, show vertical list
    if (isWideScreen) {
      return _buildVerticalList(context, appState, selectedOrg);
    }

    // For mobile, show horizontal row
    return _buildHorizontalRow(context, appState, selectedOrg);
  }

  Widget _buildVerticalList(BuildContext context, AppState appState, selectedOrg) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Icon(Icons.location_on, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Sites',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => CreateSiteDialog(
                        organizationId: selectedOrg.id,
                      ),
                    );
                  },
                  tooltip: 'Add site',
                ),
              ],
            ),
          ),
          // Sites list
          Expanded(
            child: StreamBuilder<List<Site>>(
              stream: SiteService().getSites(selectedOrg.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'Error loading sites: ${snapshot.error}',
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final sites = snapshot.data ?? [];

                if (sites.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.location_off,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No sites yet',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Create your first site to get started',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // Auto-select first site if none selected
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (appState.selectedSite == null && sites.isNotEmpty) {
                    appState.setSelectedSite(sites.first);
                  }
                });

                return ListView.builder(
                  itemCount: sites.length,
                  itemBuilder: (context, index) {
                    final site = sites[index];
                    final isSelected = appState.selectedSite?.id == site.id;

                    return ListTile(
                      dense: true,
                      selected: isSelected,
                      selectedTileColor: const Color(0xFF2D53DA).withValues(alpha: 0.1),
                      leading: Icon(
                        Icons.location_on,
                        color: isSelected ? const Color(0xFF2D53DA) : Colors.grey,
                        size: 20,
                      ),
                      title: Text(
                        site.name,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? const Color(0xFF2D53DA) : Colors.black87,
                        ),
                      ),
                      subtitle: site.address.isNotEmpty
                          ? Text(
                              site.address,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Active indicator
                          if (site.isActive)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            )
                          else
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.grey[400],
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      onTap: () {
                        appState.setSelectedSite(site);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalRow(BuildContext context, AppState appState, selectedOrg) {

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: StreamBuilder<List<Site>>(
        stream: SiteService().getSites(selectedOrg.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error loading sites',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            );
          }

          final sites = snapshot.data ?? [];

          if (sites.isEmpty) {
            return Center(
              child: Text(
                'No sites - tap + to create',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            );
          }

          // Auto-select first site if none selected
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (appState.selectedSite == null && sites.isNotEmpty) {
              appState.setSelectedSite(sites.first);
            }
          });

          return Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: sites.map((site) {
                      final isSelected = appState.selectedSite?.id == site.id;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () {
                            appState.setSelectedSite(site);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF2D53DA)
                                  : Colors.grey[200],
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 16,
                                  color: isSelected ? Colors.white : Colors.grey[700],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  site.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected ? Colors.white : Colors.black87,
                                  ),
                                ),
                                if (site.isActive) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: isSelected ? Colors.white : Colors.green,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => CreateSiteDialog(
                      organizationId: selectedOrg.id,
                    ),
                  );
                },
                tooltip: 'Add site',
              ),
            ],
          );
        },
      ),
    );
  }
}
