import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import '../../models/zone.dart' as models;
import '../../services/zone_service.dart';
import '../create_zone_dialog.dart';
import '../edit_zone_dialog.dart';

class ZonesPanel extends StatelessWidget {
  const ZonesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final currentOrg = appState.selectedOrganization;
    final currentSite = appState.selectedSite;

    // Don't show zones panel if no site is selected
    if (currentOrg == null || currentSite == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<List<models.Zone>>(
      stream: ZoneService().getZones(currentOrg.id, currentSite.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Error loading zones',
              style: TextStyle(color: Colors.red[300], fontSize: 12),
            ),
          );
        }

        final zones = snapshot.data ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with Add button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Zones',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    color: Colors.white,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => CreateZoneDialog(
                          orgId: currentOrg.id,
                          siteId: currentSite.id,
                        ),
                      );
                    },
                    tooltip: 'Add Zone',
                  ),
                ],
              ),
            ),

            // Zones list
            if (zones.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Icon(
                      Icons.layers_outlined,
                      color: Colors.white.withValues(alpha: 0.3),
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No zones yet',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Click + to add a zone',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: zones.length,
                  itemBuilder: (context, index) {
                    final zone = zones[index];
                    final isSelected = appState.selectedZone?.id == zone.id;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.2)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        leading: Icon(
                          Icons.location_on,
                          size: 18,
                          color: isSelected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.7),
                        ),
                        title: Text(
                          zone.name,
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.9),
                            fontSize: 13,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.more_vert, size: 16),
                          color: Colors.white.withValues(alpha: 0.7),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            _showZoneMenu(context, currentOrg.id, currentSite.id, zone);
                          },
                        ),
                        onTap: () {
                          appState.setSelectedZone(zone);
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  void _showZoneMenu(BuildContext context, String orgId, String siteId, models.Zone zone) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Edit Zone'),
            onTap: () {
              Navigator.pop(context);
              showDialog(
                context: context,
                builder: (context) => EditZoneDialog(
                  orgId: orgId,
                  siteId: siteId,
                  zone: zone,
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Delete Zone', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _confirmDelete(context, orgId, siteId, zone);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, String orgId, String siteId, models.Zone zone) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Zone?'),
        content: Text(
          'Are you sure you want to delete "${zone.name}"? This will also delete all sensors in this zone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await ZoneService().deleteZone(orgId, siteId, zone.id);
                if (context.mounted) {
                  Navigator.pop(context);
                  // Clear selected zone if it was deleted
                  final appState = Provider.of<AppState>(context, listen: false);
                  if (appState.selectedZone?.id == zone.id) {
                    appState.selectedZone = null;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${zone.name} deleted')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error deleting zone: $e')),
                  );
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
