import 'package:agrivoltaics_flutter_app/services/historical_series_service.dart';
import 'package:agrivoltaics_flutter_app/services/readings_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';
import 'package:agrivoltaics_flutter_app/services/formatters_service.dart';

class GraphCardWidget extends StatefulWidget {
  final HistoricalGraph graph;
  final Map<String, String> zoneLookup;
  final bool isDesktop;
  final bool isMobileLandscape;
  final PickerDateRange dateRange;
  final String interval;

  const GraphCardWidget({
    super.key,
    required this.graph,
    required this.zoneLookup,
    required this.isDesktop,
    required this.isMobileLandscape,
    required this.dateRange,
    required this.interval,
  });

  @override
  State<GraphCardWidget> createState() => _GraphCardWidgetState();
}

class _GraphCardWidgetState extends State<GraphCardWidget> {
  late final TrackballBehavior _trackballBehavior;
  int? _lastSelectedDataPointIndex;
  bool _trackballDismissedByOutsideTap = false;

  @override
  void initState() {
    super.initState();
    _trackballBehavior = TrackballBehavior(
      enable: true,
      activationMode: ActivationMode.singleTap,
      lineType: TrackballLineType.vertical,
      lineWidth: 1,
      shouldAlwaysShow: true,
      tooltipDisplayMode: TrackballDisplayMode.groupAllPoints,
      tooltipAlignment: ChartAlignment.near,
      tooltipSettings: InteractiveTooltip(
        format:
            'series.name - point.x - point.y${_unit.isEmpty ? '' : ' $_unit'}',
        canShowMarker: true,
      ),
    );
  }

  String get _unit =>
      widget.graph.unit != null && widget.graph.unit!.isNotEmpty
      ? '(${widget.graph.unit})'
      : '';

  @override
  Widget build(BuildContext context) {
    final readingsService = ReadingsService();
    final formattersService = FormattersService();
    final title = readingsService.getReadingName(widget.graph.field);
    final unit = _unit.isEmpty ? '' : ' $_unit';
    final sortedSeries = widget.graph.series.toList()
      ..sort((a, b) {
        final aName = (widget.zoneLookup[a.zoneId] ?? a.zoneId).toLowerCase();
        final bName = (widget.zoneLookup[b.zoneId] ?? b.zoneId).toLowerCase();
        return aName.compareTo(bName);
      });
    final chartHeight = widget.isDesktop
      ? 350.0
      : widget.isMobileLandscape
        ? 280.0
        : 240.0;

    final hasData = widget.graph.series.any((series) => series.points.isNotEmpty);
    final axisConfig = _getAxisConfig(widget.dateRange, widget.interval);

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
                height: chartHeight,
                child: TapRegion(
                  onTapOutside: (_) {
                    _trackballDismissedByOutsideTap = true;
                    _lastSelectedDataPointIndex = null;
                    _trackballBehavior.hide();
                  },
                  child: MouseRegion(
                    onExit: (_) {
                      final index = _lastSelectedDataPointIndex;
                      if (index == null || _trackballDismissedByOutsideTap) {
                        return;
                      }
                      // Syncfusion hides trackball on pointer exit; restore the
                      // last selected point so values stay sticky until next input.
                      Future<void>.delayed(Duration.zero, () {
                        if (!mounted || _trackballDismissedByOutsideTap) {
                          return;
                        }
                        _trackballBehavior.showByIndex(index);
                      });
                    },
                    child: SfCartesianChart(
                    onTrackballPositionChanging: (TrackballArgs args) {
                      final pointIndex = args.chartPointInfo.dataPointIndex;
                      final seriesIndex = args.chartPointInfo.seriesIndex;

                      if (pointIndex != null) {
                        _trackballDismissedByOutsideTap = false;
                        _lastSelectedDataPointIndex = pointIndex;
                      }

                      if (pointIndex == null || seriesIndex == null) {
                        return;
                      }

                      final series = sortedSeries[seriesIndex];
                      final point = series.points[pointIndex];

                      args.chartPointInfo.label =
                          '${widget.zoneLookup[series.zoneId] ?? series.zoneId} - '
                          '${axisConfig.dateFormat.format(point.time)} - '
                          '${formattersService.formatNumber(point.value)}'
                          '${_unit.isEmpty ? '' : ' $_unit'}';
                    },
                      legend: const Legend(
                        isVisible: true,
                        position: LegendPosition.bottom,
                        overflowMode: LegendItemOverflowMode.wrap,
                      ),
                      primaryXAxis: DateTimeAxis(
                        minimum: widget.dateRange.startDate,
                        maximum: widget.dateRange.endDate,
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
                      primaryYAxis: const NumericAxis(
                        majorGridLines: MajorGridLines(width: 0.5),
                      ),
                      trackballBehavior: _trackballBehavior,
                      series: sortedSeries.map((series) {
                        return LineSeries<HistoricalPoint, DateTime>(
                          name: widget.zoneLookup[series.zoneId] ?? series.zoneId,
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
