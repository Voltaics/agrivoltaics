import 'package:agrivoltaics_flutter_app/models/zone.dart';
import 'package:agrivoltaics_flutter_app/services/readings_service.dart';
import 'package:flutter/material.dart';

typedef OnApplyFilters = void Function();
typedef OnZoneSelected = void Function(String zoneId, bool selected);
typedef OnReadingSelected = void Function(String reading, bool selected);

class FilterCardWidget extends StatelessWidget {
  final List<Zone> zones;
  final Set<String> selectedZoneIds;
  final Set<String> selectedReadings;
  final OnApplyFilters onApplyFilters;
  final OnZoneSelected onZoneSelected;
  final OnReadingSelected onReadingSelected;
  final Set<String> availableReadings;

  const FilterCardWidget({
    super.key,
    required this.zones,
    required this.selectedZoneIds,
    required this.selectedReadings,
    required this.onApplyFilters,
    required this.onZoneSelected,
    required this.onReadingSelected,
    required this.availableReadings,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Filters',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onApplyFilters,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Apply'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Zones',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: zones.isEmpty
                  ? [
                      const Chip(
                        label: Text('No zones available'),
                      ),
                    ]
                  : zones.map((zone) {
                      final isSelected = selectedZoneIds.contains(zone.id);
                      return FilterChip(
                        label: Text(zone.name),
                        selected: isSelected,
                        onSelected: (value) {
                          onZoneSelected(zone.id, value);
                        },
                      );
                    }).toList(),
            ),
            const SizedBox(height: 16),
            const Text(
              'Readings',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: availableReadings.map((reading) {
                final readingsService = ReadingsService();
                final isSelected = selectedReadings.contains(reading);
                return FilterChip(
                  label: Text(readingsService.getReadingName(reading)),
                  selected: isSelected,
                  onSelected: (value) {
                    onReadingSelected(reading, value);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
