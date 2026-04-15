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
import '../../responsive/app_viewport.dart';

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
    final viewportInfo = AppViewportInfo.fromMediaQuery(MediaQuery.of(context));
    final selectedOrg = appState.selectedOrganization;
    final selectedSite = appState.selectedSite;
    final selectedZone = appState.selectedZone;

    return Padding(
      padding: viewportInfo.isMobileLandscape
          ? const EdgeInsets.symmetric(horizontal: 12)
          : EdgeInsets.zero,
      child: _buildContent(
        selectedOrg,
        selectedSite,
        selectedZone,
        isDesktop: viewportInfo.isDesktop,
      ),
    );
  }

  Widget _buildScrollableHeader() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SensorConfigBar(
          zoneService: _zoneService,
          sensorService: _sensorService,
        ),
        const SiteZoneBreadcrumb(),
      ],
    );
  }

  Widget _buildContent(
    dynamic selectedOrg,
    dynamic selectedSite,
    dynamic selectedZone, {
    required bool isDesktop,
  }) {
    if (isDesktop && (selectedOrg == null || selectedSite == null)) {
      return _buildDesktopEmptyView();
    }

    // Check if org and site are selected
    if (selectedOrg == null || selectedSite == null) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _buildScrollableHeader(),
            const EmptyStateWidget(),
          ],
        ),
      );
    }

    // Case 1: Site + Zone selected - Show single zone card
    if (selectedZone != null) {
      return _buildSingleZoneView(selectedOrg.id, selectedSite.id, selectedZone);
    }

    // Case 2: Site only selected - Show all zones
    return _buildAllZonesView(selectedOrg.id, selectedSite.id, isDesktop: isDesktop);
  }

  // Build view for single zone (site + zone selected)
  Widget _buildSingleZoneView(String orgId, String siteId, dynamic zone) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      child: Column(
        children: [
          _buildScrollableHeader(),
          ZoneCard(
            orgId: orgId,
            siteId: siteId,
            zone: zone as Zone,
          ),
        ],
      ),
    );
  }

  // Build view for all zones (site only selected)
  Widget _buildAllZonesView(String orgId, String siteId, {required bool isDesktop}) {
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

        if (isDesktop && zones.isEmpty) {
          return _buildDesktopEmptyView();
        }

        if (zones.isEmpty) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _buildScrollableHeader(),
                const EmptyStateWidget(),
              ],
            ),
          );
        }

        // Check if any zones have readings
        final zonesWithReadings = zones.where((zone) => zone.readings.isNotEmpty).toList();

        if (isDesktop && zonesWithReadings.isEmpty) {
          return _buildDesktopEmptyView();
        }

        if (zonesWithReadings.isEmpty) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _buildScrollableHeader(),
                const EmptyStateWidget(),
              ],
            ),
          );
        }

        if (!isDesktop) {
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
            itemCount: zonesWithReadings.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildScrollableHeader();
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ZoneCard(
                  orgId: orgId,
                  siteId: siteId,
                  zone: zonesWithReadings[index - 1],
                ),
              );
            },
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildScrollableHeader(),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = (constraints.maxWidth - 12) / 2;
                  final useTwoColumns = constraints.maxWidth >= 900;

                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: zonesWithReadings.map((zone) {
                      return SizedBox(
                        width: useTwoColumns ? cardWidth : constraints.maxWidth,
                        child: ZoneCard(
                          orgId: orgId,
                          siteId: siteId,
                          zone: zone,
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDesktopEmptyView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _buildScrollableHeader(),
                const EmptyStateWidget(),
              ],
            ),
          ),
        );
      },
    );
  }
}
