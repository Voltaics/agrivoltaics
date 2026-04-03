import 'package:agrivoltaics_flutter_app/services/historical_series_service.dart';
import 'package:agrivoltaics_flutter_app/services/readings_service.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';
import 'graph_card.dart';

class ResultsSectionWidget extends StatelessWidget {
  final Future<HistoricalResponse>? futureResponse;
  final String? errorMessage;
  final Set<String> selectedZoneIds;
  final Set<String> selectedReadings;
  final Map<String, String> zoneLookup;
  final bool isDesktop;
  final bool isMobileLandscape;
  final PickerDateRange dateRange;

  const ResultsSectionWidget({
    super.key,
    required this.futureResponse,
    required this.errorMessage,
    required this.selectedZoneIds,
    required this.selectedReadings,
    required this.zoneLookup,
    required this.isDesktop,
    required this.isMobileLandscape,
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

        final readingsService = ReadingsService();
        final sortedGraphs = response.graphs.toList()
          ..sort(
            (a, b) => readingsService
                .getReadingName(a.field)
                .toLowerCase()
                .compareTo(readingsService.getReadingName(b.field).toLowerCase()),
          );

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
            if (!isDesktop)
              ...sortedGraphs.map((graph) {
                return GraphCardWidget(
                  graph: graph,
                  zoneLookup: zoneLookup,
                  isDesktop: isDesktop,
                  isMobileLandscape: isMobileLandscape,
                  dateRange: dateRange,
                  interval: response.interval,
                );
              })
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final maxWidth = constraints.maxWidth;
                  final crossAxisCount = maxWidth >= 2100
                      ? 3
                      : maxWidth >= 1300
                          ? 2
                          : 1;
                  const spacing = 12.0;
                  final totalSpacing = spacing * (crossAxisCount - 1);
                  final itemWidth = (maxWidth - totalSpacing) / crossAxisCount;
                    const targetItemHeight = 460.0;
                  final childAspectRatio =
                      (itemWidth / targetItemHeight).clamp(0.8, 2.2);

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: sortedGraphs.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: spacing,
                      mainAxisSpacing: spacing,
                      childAspectRatio: childAspectRatio,
                    ),
                    itemBuilder: (context, index) {
                      final graph = sortedGraphs[index];
                      return GraphCardWidget(
                        graph: graph,
                        zoneLookup: zoneLookup,
                        isDesktop: isDesktop,
                        isMobileLandscape: isMobileLandscape,
                        dateRange: dateRange,
                        interval: response.interval,
                      );
                    },
                  );
                },
              ),
          ],
        );
      },
    );
  }
}
