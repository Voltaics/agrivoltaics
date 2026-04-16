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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.help_outline),
                tooltip: 'How to Add a Sensor',
                onPressed: () => _showAddSensorHelpDialog(context),
              ),
              // Options button
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () {
                  final appState = Provider.of<AppState>(context, listen: false);
                  if (appState.selectedZone == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('To edit sensor parameters, you must first select a specific Zone using the drop-down menu below for the site shown.'),
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
        ],
      ),
    );
  }

  void _showAddSensorHelpDialog(BuildContext context) {
    const helpInstructions = '''To add a sensor to a zone:

1. On the stationary sensors page, select the site and zone to get the zone selected. After the zone is selected, click the gear icon to get to the stationary sensor dialog for that zone.

2. Once this dialog is open, click the plus icon in the top right to add a sensor.

3. You will get to an "Add New Sensor" dialog. In this dialog name the sensor and supply any information that you feel is necessary. Add whatever readings that particular sensor supplies.

4. After adding the sensor, if you have multiple sensors in the same zone it will ask which sensor you want to use as the primary sensor. The primary sensor is used in historical data while it is considered the primary. Select which sensor you want to be the primary sensor for those readings.

5. Then the app will show a box with the sensor configuration parameters. These are important because these are what you will fill into the arduino code for that sensor box. If you click OK before seeing these you can get these back by going back to the sensor configuration menu for that zone and click on the info icon for that sensor.

6. When you have these values, before you deploy the arduino code to the arduino for the sensor box, fill them in to the respective fields. You will see constants in the code:
ORGANIZATION_ID
SITE_ID
ZONE_ID
Fill these in with the necessary values if they haven't been already. If you have multiple sensors for the zone these will only be filled in when you fill them for the first sensor.

7. Then you need to put the ID in for the sensor. If you are adding a light sensor the constant you would fill in would be SENSOR_ID_LIGHT.

8. After filling in all the IDs in the arduino code, deploy it to the arduino and the sensor box is ready to push data to the cloud.

NOTE: This guide does not explain how to add sensors beyond what is currently implemented for the previous OMID Vineyard sensor boxes in the arduino code.''';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('How to Add a Sensor'),
        content: const SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(helpInstructions),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
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
