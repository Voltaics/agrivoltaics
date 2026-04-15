import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import '../../models/zone.dart';
import '../../services/zone_service.dart';
import '../../services/sensor_service.dart';
import '../home/site_zone_breadcrumb.dart';
import 'widgets/zone_card.dart';
import 'widgets/empty_state_widget.dart';
import 'widgets/sensor_config_bar.dart';

class StationaryDashboardPage extends StatefulWidget {
  const StationaryDashboardPage({super.key});

  @override
  State<StationaryDashboardPage> createState() => _StationaryDashboardPageState();
}

class _StationaryDashboardPageState extends State<StationaryDashboardPage> {
  final ZoneService _zoneService = ZoneService();
  final SensorService _sensorService = SensorService();

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final selectedOrg = appState.selectedOrganization;
    final selectedSite = appState.selectedSite;
    final selectedZone = appState.selectedZone;

    return Column(
      children: [
        // Title row with options button
        SensorConfigBar(
          zoneService: _zoneService,
          sensorService: _sensorService,
        ),

        // Site > Zone breadcrumb
        const SiteZoneBreadcrumb(),

        // Main content area
        Expanded(
          child: _buildContent(selectedOrg, selectedSite, selectedZone),
        ),
      ],
    );
  }

  Widget _buildContent(dynamic selectedOrg, dynamic selectedSite, dynamic selectedZone) {
    // Check if org and site are selected
    if (selectedOrg == null || selectedSite == null) {
      return const EmptyStateWidget();
    }

    // Case 1: Site + Zone selected - Show single zone card
    if (selectedZone != null) {
      return _buildSingleZoneView(selectedOrg.id, selectedSite.id, selectedZone);
    }

    // Case 2: Site only selected - Show all zones
    return _buildAllZonesView(selectedOrg.id, selectedSite.id);
  }

  // Build view for single zone (site + zone selected)
  Widget _buildSingleZoneView(String orgId, String siteId, dynamic zone) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      child: ZoneCard(
        orgId: orgId,
        siteId: siteId,
        zone: zone as Zone,
      ),
    );
  }

  // Build view for all zones (site only selected)
  Widget _buildAllZonesView(String orgId, String siteId) {
    return StreamBuilder<List<Zone>>(
      stream: _zoneService.getZones(orgId, siteId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading zones: ${snapshot.error}'),
          );
        }

        final zones = snapshot.data ?? [];

        if (zones.isEmpty) {
          return const EmptyStateWidget();
        }

        // Check if any zones have readings
        final zonesWithReadings = zones.where((zone) => zone.readings.isNotEmpty).toList();

        if (zonesWithReadings.isEmpty) {
          return const EmptyStateWidget();
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
          itemCount: zonesWithReadings.length,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ZoneCard(
                orgId: orgId,
                siteId: siteId,
                zone: zonesWithReadings[index],
              ),
            );
          },
        );
      },
    );
  }
}
