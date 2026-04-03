import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';
import '../../../models/zone.dart';
import '../../../services/formatters_service.dart';
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
    final formattersService = FormattersService();
    final sortedReadings = zone.readings.entries.toList()
      ..sort(
        (a, b) => formattersService
            .formatReadingName(a.key)
            .toLowerCase()
            .compareTo(formattersService.formatReadingName(b.key).toLowerCase()),
      );

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
            const SizedBox(height: 16),

            // Readings list
            if (zone.readings.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No readings configured for this zone',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                  ),
                ),
              )
            else
              ...sortedReadings.map((entry) {
                final readingName = entry.key;
                final sensorId = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ReadingCard(
                    orgId: orgId,
                    siteId: siteId,
                    zoneId: zone.id,
                    readingName: readingName,
                    sensorId: sensorId,
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
