import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';
import '../../../models/sensor.dart';
import '../../../models/zone.dart';
import '../../../services/formatters_service.dart';
import '../../../services/sensor_service.dart';
import 'reading_card.dart';

/// Widget for displaying a single zone card with its readings
class ZoneCard extends StatelessWidget {
  final String orgId;
  final String siteId;
  final Zone zone;

  const ZoneCard({
    required this.orgId,
    required this.siteId,
    required this.zone,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final sensorService = SensorService();
    final formattersService = FormattersService();
    final sortedReadings = zone.readings.entries.toList()
      ..sort(
        (a, b) => formattersService
            .formatReadingName(a.key)
            .toLowerCase()
            .compareTo(formattersService.formatReadingName(b.key).toLowerCase()),
      );

    return StreamBuilder<List<Sensor>>(
      stream: sensorService.getSensors(orgId, siteId, zone.id),
      builder: (context, snapshot) {
        final sensors = snapshot.data ?? const <Sensor>[];
        final sensorsById = {
          for (final sensor in sensors) sensor.id: sensor,
        };

        DateTime? newestReadingDateTime;
        for (final entry in sortedReadings) {
          final sensor = sensorsById[entry.value];
          final field = sensor?.fields[entry.key];
          final timestamp = field?.lastUpdated;
          if (timestamp != null &&
              (newestReadingDateTime == null ||
                  timestamp.isAfter(newestReadingDateTime))) {
            newestReadingDateTime = timestamp;
          }
        }

        final zoneDataDateTime = newestReadingDateTime ?? zone.updatedAt;

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Zone name header
                Text(
                  zone.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Text(
                      'Data datetime: ',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        formattersService.formatDateAndTime(zoneDataDateTime),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Readings list
                if (zone.readings.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No readings configured for this zone',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 14,
                      ),
                    ),
                  )
                else
                  ...sortedReadings.map((entry) {
                    final readingName = entry.key;
                    final sensorId = entry.value;
                    final sensor = sensorsById[sensorId];
                    final field = sensor?.fields[readingName];

                    String? error;
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      error = null;
                    } else if (snapshot.hasError) {
                      error = 'Unable to load sensor data';
                    } else if (sensor == null) {
                      error = 'Sensor not found';
                    } else if (field == null) {
                      error = 'Reading not available';
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ReadingCard(
                        orgId: orgId,
                        siteId: siteId,
                        zoneId: zone.id,
                        readingName: readingName,
                        value: field?.currentValue,
                        unit: field?.unit,
                        readingLastUpdated: field?.lastUpdated,
                        zoneDataDateTime: zoneDataDateTime,
                        isLoading:
                            snapshot.connectionState == ConnectionState.waiting,
                        error: error,
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }
}
