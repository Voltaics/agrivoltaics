import 'package:agrivoltaics_flutter_app/services/historical_series_service.dart';
import 'package:agrivoltaics_flutter_app/services/readings_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';

class GraphCardWidget extends StatelessWidget {
  final HistoricalGraph graph;
  final Map<String, String> zoneLookup;
  final bool isWideScreen;
  final PickerDateRange dateRange;

  const GraphCardWidget({
    super.key,
    required this.graph,
    required this.zoneLookup,
    required this.isWideScreen,
    required this.dateRange,
  });

  @override
  Widget build(BuildContext context) {
    final readingsService = ReadingsService();
    final title = readingsService.getReadingName(graph.field);
    final unit = graph.unit != null && graph.unit!.isNotEmpty
        ? ' (${graph.unit})'
        : '';

    final hasData = graph.series.any((series) => series.points.isNotEmpty);
    final dateFormat = _getDateFormat(dateRange);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$title$unit',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (!hasData)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No data points in this range.')),
              )
            else
              SizedBox(
                height: isWideScreen ? 320 : 240,
                child: SfCartesianChart(
                  legend: Legend(
                    isVisible: true,
                    position: LegendPosition.bottom,
                    overflowMode: LegendItemOverflowMode.wrap,
                  ),
                  primaryXAxis: DateTimeAxis(
                    minimum: dateRange.startDate,
                    maximum: dateRange.endDate,
                    edgeLabelPlacement: EdgeLabelPlacement.shift,
                    dateFormat: dateFormat,
                  ),
                  primaryYAxis: NumericAxis(
                    majorGridLines: const MajorGridLines(width: 0.5),
                  ),
                  trackballBehavior: TrackballBehavior(
                    enable: true,
                    activationMode: ActivationMode.singleTap,
                    lineType: TrackballLineType.vertical,
                    lineWidth: 1,
                    shouldAlwaysShow: false,
                    tooltipDisplayMode: TrackballDisplayMode.nearestPoint,
                    tooltipSettings: InteractiveTooltip(
                      format: 'series.name - point.x - point.y${unit.isEmpty ? '' : ' $unit'}',
                      canShowMarker: true,
                    ),
                  ),
                  series: graph.series.map((series) {
                    return LineSeries<HistoricalPoint, DateTime>(
                      name: zoneLookup[series.zoneId] ?? series.zoneId,
                      dataSource: series.points,
                      xValueMapper: (point, _) => point.time,
                      yValueMapper: (point, _) => point.value,
                      markerSettings: MarkerSettings(
                        isVisible: series.points.length <= 8,
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  DateFormat _getDateFormat(PickerDateRange dateRange) {
    final start = dateRange.startDate;
    final end = dateRange.endDate;

    if (start == null || end == null) {
      return DateFormat('MM/dd');
    }

    // Check if range is less than 192 hours
    final duration = end.difference(start);
    if (duration.inHours < 192) {
      return DateFormat('MM/dd\nHH:mm');
    }

    return DateFormat('MM/dd');
  }
}