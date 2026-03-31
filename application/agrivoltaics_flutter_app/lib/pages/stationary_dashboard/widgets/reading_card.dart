import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/sensor.dart';
import '../../../services/sensor_service.dart';
import '../../../services/formatters_service.dart';

/// Readings older than this are considered stale.
const _staleThreshold = Duration(minutes: 30);

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
          return _buildReadingCardUI(readingName, null, null, null, formattersService, isLoading: true);
        }

        final sensor = snapshot.data;
        if (sensor == null) {
          return _buildReadingCardUI(readingName, null, null, null, formattersService, error: 'Sensor not found');
        }

        // Get the field from the sensor that matches this reading name
        final field = sensor.fields[readingName];
        if (field == null) {
          return _buildReadingCardUI(readingName, null, null, null, formattersService, error: 'Reading not available');
        }

        return _buildReadingCardUI(
          readingName,
          field.currentValue,
          field.unit,
          field.lastUpdated,
          formattersService,
        );
      },
    );
  }

  /// Build the UI for the reading card.
  /// [now] is captured once per snapshot to avoid repeated DateTime.now() calls.
  static Widget _buildReadingCardUI(
    String readingName,
    double? value,
    String? unit,
    DateTime? lastUpdated,
    FormattersService formattersService, {
    bool isLoading = false,
    String? error,
  }) {
    final now = DateTime.now();
    final isStale = lastUpdated == null ||
        now.difference(lastUpdated) > _staleThreshold;
    final staleFlag = !isLoading && error == null && isStale;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: staleFlag
            ? const BorderSide(color: AppColors.amber, width: 1)
            : BorderSide(color: AppColors.scaffoldBackground),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Reading name (+ stale icon)
                Row(
                  children: [
                    Text(
                      formattersService.formatReadingName(readingName),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (staleFlag) ...[
                      const SizedBox(width: 6),
                      const Tooltip(
                        message: 'Data may be outdated (>30 min)',
                        child: Icon(Icons.warning_amber_rounded,
                            size: 16, color: AppColors.amber),
                      ),
                    ],
                  ],
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
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textMuted,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else if (value != null)
                  Row(
                    children: [
                      Text(
                        value.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textOnLight,
                        ),
                      ),
                      if (unit != null && unit.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Text(
                          unit,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  )
                else
                  Text(
                    'No data',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textMuted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),

            // Last updated timestamp (shown below value row)
            if (!isLoading && error == null) ...[
              const SizedBox(height: 4),
              Text(
                lastUpdated != null
                    ? 'Updated ${DateFormat('M/d HH:mm').format(lastUpdated.toLocal())}'
                    : 'No timestamp',
                style: TextStyle(
                  fontSize: 11,
                  color: staleFlag ? AppColors.amber : AppColors.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
