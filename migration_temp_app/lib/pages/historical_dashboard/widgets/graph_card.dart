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
  final String interval;

  const GraphCardWidget({
    super.key,
    required this.graph,
    required this.zoneLookup,
    required this.isWideScreen,
    required this.dateRange,
    required this.interval,
  });

  @override
  Widget build(BuildContext context) {
    final readingsService = ReadingsService();
    final title = readingsService.getReadingName(graph.field);
    final unit = graph.unit != null && graph.unit!.isNotEmpty
        ? ' (${graph.unit})'
        : '';

    final hasData = graph.series.any((series) => series.points.isNotEmpty);
    final axisConfig = _getAxisConfig(dateRange, interval);

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
                    dateFormat: axisConfig.dateFormat,
                    intervalType: axisConfig.intervalType,
                    interval: axisConfig.axisInterval,
                    axisLabelFormatter: (AxisLabelRenderDetails details) {
                      final dt = DateTime.fromMillisecondsSinceEpoch(
                        details.value.toInt(),
                      );
                      return ChartAxisLabel(
                        axisConfig.labelDateFormat.format(dt),
                        details.textStyle,
                      );
                    },
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

  // Each threshold guarantees at most 8 tick labels regardless of screen size.
  // dateFormat: full 'MM/dd HH:mm' for hour intervals — used by trackball point.x.
  // labelDateFormat: compact format used exclusively for axis tick labels.
  ({DateTimeIntervalType intervalType, double axisInterval, DateFormat dateFormat, DateFormat labelDateFormat}) _getAxisConfig(
    PickerDateRange dateRange,
    String interval,
  ) {
    final start = dateRange.startDate;
    final end = dateRange.endDate;
    final duration = (start != null && end != null)
        ? end.difference(start)
        : const Duration(days: 7);
    final h = duration.inHours;
    final hourTooltipFmt = DateFormat('MM/dd HH:mm');

    if (h <= 8) {
      return (
        intervalType: DateTimeIntervalType.hours,
        axisInterval: 1.0,
        dateFormat: hourTooltipFmt,
        labelDateFormat: DateFormat('HH:mm'),
      );
    }
    if (h <= 16) {
      return (
        intervalType: DateTimeIntervalType.hours,
        axisInterval: 2.0,
        dateFormat: hourTooltipFmt,
        labelDateFormat: DateFormat('HH:mm'),
      );
    }
    if (h <= 24) {
      return (
        intervalType: DateTimeIntervalType.hours,
        axisInterval: 3.0,
        dateFormat: hourTooltipFmt,
        labelDateFormat: DateFormat('HH:mm'),
      );
    }
    if (h <= 48) {
      return (
        intervalType: DateTimeIntervalType.hours,
        axisInterval: 6.0,
        dateFormat: hourTooltipFmt,
        labelDateFormat: DateFormat('MM/dd\nHH:mm'),
      );
    }
    if (h <= 96) {
      return (
        intervalType: DateTimeIntervalType.hours,
        axisInterval: 12.0,
        dateFormat: hourTooltipFmt,
        labelDateFormat: DateFormat('MM/dd\nHH:mm'),
      );
    }
    if (h <= 192) {
      return (
        intervalType: DateTimeIntervalType.days,
        axisInterval: 1.0,
        dateFormat: hourTooltipFmt,
        labelDateFormat: DateFormat('MM/dd'),
      );
    }
    if (h <= 384) {
      return (
        intervalType: DateTimeIntervalType.days,
        axisInterval: 2.0,
        dateFormat: DateFormat('MM/dd'),
        labelDateFormat: DateFormat('MM/dd'),
      );
    }
    if (h <= 1344) {
      return (
        intervalType: DateTimeIntervalType.days,
        axisInterval: 7.0,
        dateFormat: DateFormat('MM/dd'),
        labelDateFormat: DateFormat('MM/dd'),
      );
    }
    return (
      intervalType: DateTimeIntervalType.months,
      axisInterval: 1.0,
      dateFormat: DateFormat('MM/yy'),
      labelDateFormat: DateFormat('MM/yy'),
    );
  }
}