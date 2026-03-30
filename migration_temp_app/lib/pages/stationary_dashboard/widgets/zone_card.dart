import 'package:flutter/material.dart';
import '../../../models/zone.dart';
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
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              )
            else
              ...zone.readings.entries.map((entry) {
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
