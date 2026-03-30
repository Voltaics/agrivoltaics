import 'package:agrivoltaics_flutter_app/services/historical_series_service.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';
import 'graph_card.dart';

class ResultsSectionWidget extends StatelessWidget {
  final Future<HistoricalResponse>? futureResponse;
  final String? errorMessage;
  final Set<String> selectedZoneIds;
  final Set<String> selectedReadings;
  final Map<String, String> zoneLookup;
  final bool isWideScreen;
  final PickerDateRange dateRange;

  const ResultsSectionWidget({
    super.key,
    required this.futureResponse,
    required this.errorMessage,
    required this.selectedZoneIds,
    required this.selectedReadings,
    required this.zoneLookup,
    required this.isWideScreen,
    required this.dateRange,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedZoneIds.isEmpty || selectedReadings.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 24),
        child: Center(
          child: Text('Select at least one zone and reading to load data.'),
        ),
      );
    }

    if (futureResponse == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 24),
        child: Center(
          child: Text('Tap Apply to load historical data.'),
        ),
      );
    }

    if (errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Center(
          child: Text(errorMessage!),
        ),
      );
    }

    return FutureBuilder<HistoricalResponse>(
      future: futureResponse,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Center(
              child: Text('Failed to load data: ${snapshot.error}'),
            ),
          );
        }

        final response = snapshot.data;
        if (response == null || response.graphs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(child: Text('No historical data available.')),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  const Icon(Icons.timeline, size: 18),
                  const SizedBox(width: 8),
                  Text('Interval: ${response.interval}'),
                ],
              ),
            ),
            ...response.graphs.map((graph) {
              return GraphCardWidget(
                graph: graph,
                zoneLookup: zoneLookup,
                isWideScreen: isWideScreen,
                dateRange: dateRange,
                interval: response.interval,
              );
            }).toList(),
          ],
        );
      },
    );
  }
}
