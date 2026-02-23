import 'package:agrivoltaics_flutter_app/models/site.dart' as models;
import 'package:agrivoltaics_flutter_app/models/zone.dart';
import 'package:agrivoltaics_flutter_app/services/historical_series_service.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';

import 'filter_card.dart';
import 'results_section.dart';

/// Handles zone loading, selection syncing, and renders the filter card and
/// results section for the Historical Dashboard.
///
/// Manages its own [_lastSyncedSiteId] so that selections are re-synced and
/// an initial query is triggered automatically whenever the selected site
/// changes, without requiring the parent to track this.
class ZoneSectionWidget extends StatefulWidget {
  final String orgId;
  final models.Site selectedSite;
  final Stream<List<Zone>> zoneStream;
  final Set<String> selectedZoneIds;
  final Set<String> selectedReadings;
  final String selectedAggregation;
  final VoidCallback onApplyFilters;
  final void Function(String zoneId, bool selected) onZoneSelected;
  final void Function(String reading, bool selected) onReadingSelected;
  final void Function(String aggregation) onAggregationChanged;

  /// Called when the site changes and fresh zone data arrives.
  /// The parent should use this to sync zone/reading selections.
  final void Function(List<Zone> zones) onZonesLoaded;

  /// Returns the set of available reading keys for the provided zones.
  final Set<String> Function(List<Zone> zones) availableReadings;

  final Future<HistoricalResponse>? futureResponse;
  final String? errorMessage;
  final bool isWideScreen;
  final PickerDateRange dateRange;

  const ZoneSectionWidget({
    super.key,
    required this.orgId,
    required this.selectedSite,
    required this.zoneStream,
    required this.selectedZoneIds,
    required this.selectedReadings,
    required this.selectedAggregation,
    required this.onApplyFilters,
    required this.onZoneSelected,
    required this.onReadingSelected,
    required this.onAggregationChanged,
    required this.onZonesLoaded,
    required this.availableReadings,
    required this.futureResponse,
    required this.errorMessage,
    required this.isWideScreen,
    required this.dateRange,
  });

  @override
  State<ZoneSectionWidget> createState() => _ZoneSectionWidgetState();
}

class _ZoneSectionWidgetState extends State<ZoneSectionWidget> {
  String? _lastSyncedSiteId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Zone>>(
      stream: widget.zoneStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading zones: ${snapshot.error}'),
          );
        }

        final zones = snapshot.data ?? [];

        // Only sync selections and auto-query when the site changes.
        if (_lastSyncedSiteId != widget.selectedSite.id) {
          _lastSyncedSiteId = widget.selectedSite.id;
          widget.onZonesLoaded(zones);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onApplyFilters();
          });
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilterCardWidget(
              zones: zones,
              selectedZoneIds: widget.selectedZoneIds,
              selectedReadings: widget.selectedReadings,
              onApplyFilters: widget.onApplyFilters,
              onZoneSelected: widget.onZoneSelected,
              onReadingSelected: widget.onReadingSelected,
              availableReadings: widget.availableReadings(zones),
              selectedAggregation: widget.selectedAggregation,
              onAggregationChanged: widget.onAggregationChanged,
            ),
            const SizedBox(height: 16),
            ResultsSectionWidget(
              futureResponse: widget.futureResponse,
              errorMessage: widget.errorMessage,
              selectedZoneIds: widget.selectedZoneIds,
              selectedReadings: widget.selectedReadings,
              zoneLookup: {
                for (final zone in zones) zone.id: zone.name,
              },
              isWideScreen: widget.isWideScreen,
              dateRange: widget.dateRange,
            ),
          ],
        );
      },
    );
  }
}
