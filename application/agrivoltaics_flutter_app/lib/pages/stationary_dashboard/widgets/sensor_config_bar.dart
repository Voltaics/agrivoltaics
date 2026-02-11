import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app_state.dart';
import '../../../models/zone.dart';
import '../dialogs/sensor_config_dialog.dart';
import '../../../services/sensor_service.dart';
import '../../../services/zone_service.dart';

/// Widget for the title bar with sensor configuration button
class SensorConfigBar extends StatelessWidget {
  final ZoneService zoneService;
  final SensorService sensorService;

  const SensorConfigBar({
    required this.zoneService,
    required this.sensorService,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Title
          const Text(
            'Stationary Sensors',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          // Options button
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              final appState = Provider.of<AppState>(context, listen: false);
              if (appState.selectedZone == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please select a zone to configure sensors'),
                  ),
                );
              } else {
                _showSensorConfigDialog(
                  context,
                  appState.selectedOrganization!.id,
                  appState.selectedSite!.id,
                  appState.selectedZone!,
                );
              }
            },
            tooltip: 'Sensor Configuration',
          ),
        ],
      ),
    );
  }

  /// Show sensor configuration dialog
  void _showSensorConfigDialog(
    BuildContext context,
    String orgId,
    String siteId,
    dynamic zone,
  ) {
    showDialog(
      context: context,
      builder: (context) => SensorConfigDialog(
        orgId: orgId,
        siteId: siteId,
        zone: zone as Zone,
        sensorService: sensorService,
        zoneService: zoneService,
      ),
    );
  }
}
