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
    builder: (dialogContext) {
      final media = MediaQuery.of(dialogContext);
      final isDesktop = media.size.width >= 1280;
      final maxDialogWidth = media.size.width * 0.95;
      final preferredWidth = isDesktop ? 520.0 : 520.0;
      final dialogWidth = maxDialogWidth > preferredWidth ? preferredWidth : maxDialogWidth;
      final contentMaxHeight = media.size.height * (isDesktop ? 0.46 : 0.6);

      return AlertDialog(
        title: const Text('Sensor Configuration Parameters'),
        content: SizedBox(
          width: dialogWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: contentMaxHeight),
            child: SingleChildScrollView(
              child: Column(
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
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}
