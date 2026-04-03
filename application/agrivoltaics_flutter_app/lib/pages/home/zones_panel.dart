import 'package:agrivoltaics_flutter_app/app_colors.dart';
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
              style: TextStyle(color: AppColors.error, fontSize: 12),
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
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    color: AppColors.textPrimary,
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
                    color: AppColors.textPrimary.withAlpha((0.3 * 255).toInt()),
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No zones yet',
                      style: TextStyle(
                        color: AppColors.textPrimary.withAlpha((0.5 * 255).toInt()),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Click + to add a zone',
                      style: TextStyle(
                        color: AppColors.textPrimary.withAlpha((0.4 * 255).toInt()),
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
                            ? AppColors.textPrimary.withAlpha((0.2 * 255).toInt())
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
                              : Colors.white.withAlpha((0.7 * 255).toInt()),
                        ),
                        title: Text(
                          zone.name,
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : Colors.white.withAlpha((0.9 * 255).toInt()),
                            fontSize: 13,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit, size: 16),
                          color: AppColors.textPrimary.withAlpha((0.7 * 255).toInt()),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => EditZoneDialog(
                                orgId: currentOrg.id,
                                siteId: currentSite.id,
                                zone: zone,
                              ),
                            );
                          },
                          tooltip: 'Edit zone',
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
}
