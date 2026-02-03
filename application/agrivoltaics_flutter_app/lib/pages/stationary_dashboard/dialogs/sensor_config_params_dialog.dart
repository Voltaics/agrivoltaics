import 'package:flutter/material.dart';
import '../widgets/config_row.dart';

// Shared helper to show sensor configuration parameters dialog
Future<void> showSensorConfigParamsDialog(
  BuildContext context, {
  required String orgId,
  required String siteId,
  required String zoneId,
  required String sensorId,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Sensor Configuration Parameters'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'These parameters will need to be configured in the CPU that sends the sensor data to the cloud',
          ),
          const SizedBox(height: 16),
          ConfigRow(label: 'Organization ID', value: orgId),
          ConfigRow(label: 'Site ID', value: siteId),
          ConfigRow(label: 'Zone ID', value: zoneId),
          ConfigRow(label: 'Sensor ID', value: sensorId),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
