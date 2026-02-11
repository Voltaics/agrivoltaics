import 'package:flutter/material.dart';
import '../../../models/sensor.dart';
import '../../../services/sensor_service.dart';
import '../../../services/formatters_service.dart';

/// Widget for displaying a single sensor reading card
class ReadingCard extends StatelessWidget {
  final String orgId;
  final String siteId;
  final String zoneId;
  final String readingName;
  final String sensorId;

  const ReadingCard({
    required this.orgId,
    required this.siteId,
    required this.zoneId,
    required this.readingName,
    required this.sensorId,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final sensorService = SensorService();
    final formattersService = FormattersService();

    return StreamBuilder<Sensor?>(
      stream: sensorService.getSensors(orgId, siteId, zoneId).map((sensors) {
        try {
          return sensors.firstWhere((s) => s.id == sensorId);
        } catch (e) {
          return null;
        }
      }),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildReadingCardUI(readingName, null, null, formattersService, isLoading: true);
        }

        final sensor = snapshot.data;
        if (sensor == null) {
          return _buildReadingCardUI(readingName, null, null, formattersService, error: 'Sensor not found');
        }

        // Get the field from the sensor that matches this reading name
        final field = sensor.fields[readingName];
        if (field == null) {
          return _buildReadingCardUI(readingName, null, null, formattersService, error: 'Reading not available');
        }

        return _buildReadingCardUI(
          readingName,
          field.currentValue,
          field.unit,
          formattersService,
          isOnline: sensor.isOnline,
        );
      },
    );
  }

  /// Build the UI for the reading card
  static Widget _buildReadingCardUI(
    String readingName,
    double? value,
    String? unit,
    FormattersService formattersService, {
    bool isLoading = false,
    String? error,
    bool isOnline = false,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey[300]!),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Reading name
            Text(
              formattersService.formatReadingName(readingName),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),

            // Value and unit
            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (error != null)
              Text(
                error,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                  fontStyle: FontStyle.italic,
                ),
              )
            else if (value != null)
              Row(
                children: [
                  Text(
                    value.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isOnline ? Colors.black : Colors.grey[600],
                    ),
                  ),
                  if (unit != null && unit.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text(
                      unit,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ],
              )
            else
              Text(
                'No data',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
