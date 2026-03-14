import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/zone.dart';
import '../../../models/sensor.dart';
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
    // Sort reading entries alphabetically by key
    final sortedReadings = zone.readings.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

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
            // Zone name header with latest datetime
            _ZoneHeader(
              orgId: orgId,
              siteId: siteId,
              zone: zone,
            ),
            const SizedBox(height: 16),

            // Readings list (alphabetically sorted)
            if (sortedReadings.isEmpty)
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

/// Zone header: shows zone name + the most recent lastUpdated datetime
/// derived from all sensors in this zone.
class _ZoneHeader extends StatefulWidget {
  final String orgId;
  final String siteId;
  final Zone zone;

  const _ZoneHeader({
    required this.orgId,
    required this.siteId,
    required this.zone,
  });

  @override
  State<_ZoneHeader> createState() => _ZoneHeaderState();
}

class _ZoneHeaderState extends State<_ZoneHeader> {
  // Single SensorService instance, not recreated on every build.
  final SensorService _sensorService = SensorService();

  @override
  Widget build(BuildContext context) {
    if (widget.zone.readings.isEmpty) {
      return Text(
        widget.zone.name,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      );
    }

    return StreamBuilder<List<Sensor>>(
      stream: _sensorService.getSensors(
          widget.orgId, widget.siteId, widget.zone.id),
      builder: (context, snapshot) {
        DateTime? latest;
        if (snapshot.hasData) {
          for (final sensor in snapshot.data!) {
            for (final field in sensor.fields.values) {
              if (field.lastUpdated != null) {
                if (latest == null ||
                    field.lastUpdated!.isAfter(latest)) {
                  latest = field.lastUpdated;
                }
              }
            }
          }
        }

        final dateStr = latest != null
            ? DateFormat('M/d HH:mm').format(latest!.toLocal())
            : null;

        return Row(
          children: [
            Expanded(
              child: Text(
                widget.zone.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (dateStr != null)
              Text(
                dateStr,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
          ],
        );
      },
    );
  }
}
