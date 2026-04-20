import 'package:agrivoltaics_flutter_app/app_constants.dart';
import 'package:agrivoltaics_flutter_app/app_state.dart';
import 'package:agrivoltaics_flutter_app/models/site.dart' as models;
import 'package:agrivoltaics_flutter_app/models/zone.dart';
import 'package:agrivoltaics_flutter_app/pages/historical_dashboard/dialogs/date_range_picker_dialog.dart';
import 'package:agrivoltaics_flutter_app/responsive/app_viewport.dart';
import 'package:agrivoltaics_flutter_app/services/frost_prediction_series_service.dart';
import 'package:agrivoltaics_flutter_app/services/site_service.dart';
import 'package:agrivoltaics_flutter_app/services/zone_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';

class FrostPredictionTimelineModel extends StatefulWidget {
  const FrostPredictionTimelineModel({super.key});

  @override
  State<FrostPredictionTimelineModel> createState() => _FrostPredictionTimelineModelState();
}

class _FrostPredictionTimelineModelState extends State<FrostPredictionTimelineModel> {
  final SiteService _siteService = SiteService();
  final ZoneService _zoneService = ZoneService();
  late final FrostPredictionSeriesService _service;

  static const Duration _forecastWindow = Duration(hours: 6);
  static const Color _frostChanceColor = Color(0xFFFFB300);

  final DateFormat _trackballHeaderFormat = DateFormat('MMM d, h:mm a');

  Stream<List<Zone>>? _zoneStream;
  String? _zoneStreamSiteId;

  late final TrackballBehavior _trackballBehavior;
  int? _lastSelectedDataPointIndex;
  bool _trackballDismissedByOutsideTap = false;

  @override
  void initState() {
    super.initState();
    _service = const FrostPredictionSeriesService(
      endpointUrl: AppConstants.frostPredictionSeriesEndpoint,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = context.read<AppState>();
      if (appState.frostTimelineDateRange == null) {
        final now = DateTime.now();
        final twoDaysAgo = now.subtract(const Duration(days: 2));
        appState.setFrostTimelineDateRange(PickerDateRange(twoDaysAgo, now));
      }
    });

    _trackballBehavior = TrackballBehavior(
      enable: true,
      activationMode: ActivationMode.singleTap,
      lineType: TrackballLineType.vertical,
      lineWidth: 1,
      shouldAlwaysShow: true,
      tooltipDisplayMode: TrackballDisplayMode.groupAllPoints,
      tooltipAlignment: ChartAlignment.near,
      tooltipSettings: const InteractiveTooltip(
        canShowMarker: true,
      ),
    );
  }

  Stream<List<Zone>> _getZoneStream(String orgId, String siteId) {
    if (_zoneStream == null || _zoneStreamSiteId != siteId) {
      _zoneStream = _zoneService.getZones(orgId, siteId);
      _zoneStreamSiteId = siteId;
    }
    return _zoneStream!;
  }

  Future<void> _loadTimeline() async {
    final appState = context.read<AppState>();
    final org = appState.selectedOrganization;
    final selectedSite = appState.frostTimelineSelectedSite;
    final selectedZone = appState.frostTimelineSelectedZone;
    final dateRange = appState.frostTimelineDateRange;

    if (org == null) {
      appState.setFrostTimelineError('Select an organization first.');
      return;
    }

    if (selectedSite == null) {
      appState.setFrostTimelineError('Select a site.');
      return;
    }

    if (selectedZone == null) {
      appState.setFrostTimelineError('Select a zone.');
      return;
    }

    final start = dateRange?.startDate;
    final end = dateRange?.endDate;

    if (start == null || end == null) {
      appState.setFrostTimelineError('Select a valid date range.');
      return;
    }

    appState.startFrostTimelineLoad();

    try {
      final user = FirebaseAuth.instance.currentUser;
      final idToken = user != null ? await user.getIdToken() : null;

      final response = await _service.fetchTimeline(
        organizationId: org.id,
        siteId: selectedSite.id,
        zoneId: selectedZone.id,
        start: start,
        end: end,
        timezone: selectedSite.timezone,
        idToken: idToken,
      );

      if (!mounted) return;
      appState.setFrostTimelineResponse(response);
    } catch (e) {
      if (!mounted) return;
      appState.setFrostTimelineError(e.toString());
    }
  }

  String _formatRange(PickerDateRange range) {
    final format = DateFormat('MMM d, yyyy');
    final start = range.startDate ?? DateTime.now();
    final end = range.endDate ?? start;
    return '${format.format(start)} - ${format.format(end)}';
  }

  ({DateTimeIntervalType intervalType, double axisInterval, DateFormat labelDateFormat}) _getAxisConfig(
    PickerDateRange dateRange,
  ) {
    final start = dateRange.startDate;
    final end = dateRange.endDate;
    final duration = (start != null && end != null)
        ? end.difference(start)
        : const Duration(days: 7);
    final h = duration.inHours;

    if (h <= 8) {
      return (
        intervalType: DateTimeIntervalType.hours,
        axisInterval: 1.0,
        labelDateFormat: DateFormat('HH:mm'),
      );
    }
    if (h <= 24) {
      return (
        intervalType: DateTimeIntervalType.hours,
        axisInterval: 3.0,
        labelDateFormat: DateFormat('HH:mm'),
      );
    }
    if (h <= 48) {
      return (
        intervalType: DateTimeIntervalType.hours,
        axisInterval: 6.0,
        labelDateFormat: DateFormat('MM/dd\nHH:mm'),
      );
    }
    if (h <= 192) {
      return (
        intervalType: DateTimeIntervalType.days,
        axisInterval: 1.0,
        labelDateFormat: DateFormat('MM/dd'),
      );
    }
    if (h <= 384) {
      return (
        intervalType: DateTimeIntervalType.days,
        axisInterval: 2.0,
        labelDateFormat: DateFormat('MM/dd'),
      );
    }

    return (
      intervalType: DateTimeIntervalType.days,
      axisInterval: 7.0,
      labelDateFormat: DateFormat('MM/dd'),
    );
  }

  List<_ShiftedChancePoint> _buildShiftedChancePoints(
    List<FrostTimelinePoint> rawPoints,
    DateTime visibleStart,
    DateTime visibleEnd,
  ) {
    final shifted = rawPoints
        .map(
          (p) => _ShiftedChancePoint(
            sourceTime: p.time,
            time: p.time.add(_forecastWindow),
            value: p.predictedChance,
          ),
        )
        .where(
          (p) =>
              !p.time.isBefore(visibleStart) &&
              !p.time.isAfter(visibleEnd),
        )
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    return shifted;
  }

  ({List<_ShiftedChancePoint> solid, List<_ShiftedChancePoint> dashed})
  _splitShiftedChancePointsAtNow(
    List<_ShiftedChancePoint> points,
    DateTime now,
  ) {
    if (points.isEmpty) {
      return (solid: <_ShiftedChancePoint>[], dashed: <_ShiftedChancePoint>[]);
    }

    final solid = <_ShiftedChancePoint>[];
    final dashed = <_ShiftedChancePoint>[];

    void addUnique(List<_ShiftedChancePoint> target, _ShiftedChancePoint point) {
      if (target.isEmpty ||
          target.last.time != point.time ||
          target.last.value != point.value) {
        target.add(point);
      }
    }

    if (points.length == 1) {
      if (points.first.time.isAfter(now)) {
        dashed.add(points.first);
      } else {
        solid.add(points.first);
      }
      return (solid: solid, dashed: dashed);
    }

    for (var i = 0; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];

      final currentAtOrBeforeNow =
          current.time.isBefore(now) || current.time.isAtSameMomentAs(now);
      final nextAtOrBeforeNow =
          next.time.isBefore(now) || next.time.isAtSameMomentAs(now);

      if (currentAtOrBeforeNow && nextAtOrBeforeNow) {
        addUnique(solid, current);
        addUnique(solid, next);
        continue;
      }

      if (!currentAtOrBeforeNow && !nextAtOrBeforeNow) {
        addUnique(dashed, current);
        addUnique(dashed, next);
        continue;
      }

      final totalMillis = next.time.difference(current.time).inMilliseconds;
      if (totalMillis <= 0) continue;

      final elapsedMillis = now.difference(current.time).inMilliseconds;
      final t = elapsedMillis / totalMillis;
      final interpolatedValue = current.value + ((next.value - current.value) * t);

      final boundaryPoint = _ShiftedChancePoint(
        sourceTime: current.sourceTime,
        time: now,
        value: interpolatedValue,
      );

      if (currentAtOrBeforeNow) {
        addUnique(solid, current);
        addUnique(solid, boundaryPoint);
        addUnique(dashed, boundaryPoint);
        addUnique(dashed, next);
      } else {
        addUnique(dashed, current);
        addUnique(dashed, boundaryPoint);
        addUnique(solid, boundaryPoint);
        addUnique(solid, next);
      }
    }

    return (solid: solid, dashed: dashed);
  }

  DateTime? _trackballTimeForSeriesPoint({
    required int? seriesIndex,
    required int? pointIndex,
    required List<FrostTimelinePoint> temperaturePoints,
    required List<FrostTimelinePoint> humidityPoints,
    required List<FrostTimelinePoint> soilTempPoints,
    required List<_ShiftedChancePoint> solidChancePoints,
    required List<_ShiftedChancePoint> dashedChancePoints,
  }) {
    if (seriesIndex == null || pointIndex == null || pointIndex < 0) {
      return null;
    }

    switch (seriesIndex) {
      case 0:
        return pointIndex < temperaturePoints.length
            ? temperaturePoints[pointIndex].time
            : null;
      case 1:
        return pointIndex < humidityPoints.length
            ? humidityPoints[pointIndex].time
            : null;
      case 2:
        return pointIndex < soilTempPoints.length
            ? soilTempPoints[pointIndex].time
            : null;
      case 3:
        return pointIndex < solidChancePoints.length
            ? solidChancePoints[pointIndex].time
            : null;
      case 4:
        return pointIndex < dashedChancePoints.length
            ? dashedChancePoints[pointIndex].time
            : null;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final selectedOrg = appState.selectedOrganization;
    final viewportInfo = AppViewportInfo.fromMediaQuery(MediaQuery.of(context));

    if (selectedOrg == null) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Select an organization to view frost model results.'),
        ),
      );
    }

    return StreamBuilder<List<models.Site>>(
      stream: _siteService.getSites(selectedOrg.id),
      builder: (context, siteSnapshot) {
        if (siteSnapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (siteSnapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error loading sites: ${siteSnapshot.error}'),
            ),
          );
        }

        final sites = siteSnapshot.data ?? [];

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Frost Prediction Timeline',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'View temperature, humidity, soil temperature, and frost prediction chance for a selected zone.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                if (viewportInfo.isDesktop)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildFilters(context, sites, selectedOrg.id)),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: _buildResults(context, viewportInfo)),
                    ],
                  )
                else ...[
                  _buildFilters(context, sites, selectedOrg.id),
                  const SizedBox(height: 16),
                  _buildResults(context, viewportInfo),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilters(BuildContext context, List<models.Site> sites, String orgId) {
    final appState = context.watch<AppState>();
    final selectedSite = appState.frostTimelineSelectedSite;
    final selectedZone = appState.frostTimelineSelectedZone;
    final dateRange = appState.frostTimelineDateRange ??
        PickerDateRange(
          DateTime.now().subtract(const Duration(days: 2)),
          DateTime.now(),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: selectedSite?.id,
          decoration: const InputDecoration(
            labelText: 'Site',
            border: OutlineInputBorder(),
          ),
          items: sites
              .map(
                (site) => DropdownMenuItem<String>(
                  value: site.id,
                  child: Text(site.name),
                ),
              )
              .toList(),
          onChanged: (siteId) {
            final site = sites.where((s) => s.id == siteId).firstOrNull;
            appState.setFrostTimelineSelectedSite(site);
            setState(() {
              _zoneStream = null;
              _zoneStreamSiteId = null;
            });
          },
        ),
        const SizedBox(height: 12),
        if (selectedSite == null)
          const Text('Choose a site to load zones.')
        else
          StreamBuilder<List<Zone>>(
            stream: _getZoneStream(orgId, selectedSite.id),
            builder: (context, zoneSnapshot) {
              if (zoneSnapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (zoneSnapshot.hasError) {
                return Text('Error loading zones: ${zoneSnapshot.error}');
              }

              final zones = (zoneSnapshot.data ?? [])
                  .where((z) => z.zoneChecked)
                  .toList();

              if (zones.isEmpty) {
                return const Text('No enabled zones available for this site.');
              }

              final selectedZoneStillExists =
                  zones.any((z) => z.id == selectedZone?.id);

              if (!selectedZoneStillExists && selectedZone != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  appState.setFrostTimelineSelectedZone(null);
                });
              }

              return DropdownButtonFormField<String>(
                initialValue: selectedZoneStillExists ? selectedZone?.id : null,
                decoration: const InputDecoration(
                  labelText: 'Zone',
                  border: OutlineInputBorder(),
                ),
                items: zones
                    .map(
                      (zone) => DropdownMenuItem<String>(
                        value: zone.id,
                        child: Text(zone.name),
                      ),
                    )
                    .toList(),
                onChanged: (zoneId) {
                  final zone = zones.where((z) => z.id == zoneId).firstOrNull;
                  appState.setFrostTimelineSelectedZone(zone);
                },
              );
            },
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: selectedSite == null
              ? null
              : () {
                  showDateRangePickerDialog(
                    context,
                    initialRange: dateRange,
                    onApplied: (range) {
                      appState.setFrostTimelineDateRange(range);
                    },
                  );
                },
          icon: const Icon(Icons.date_range),
          label: Text(_formatRange(dateRange)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: appState.frostTimelineIsLoading ? null : _loadTimeline,
            icon: const Icon(Icons.show_chart),
            label: const Text('Load frost timeline'),
          ),
        ),
      ],
    );
  }

  Widget _buildResults(BuildContext context, AppViewportInfo viewportInfo) {
    final appState = context.watch<AppState>();
    final response = appState.frostTimelineResponse;
    final isLoading = appState.frostTimelineIsLoading;
    final error = appState.frostTimelineErrorMessage;
        if (response == null && isLoading) {
      return const _InfoCard(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
              Text('Loading frost timeline...'),
            ],
          ),
        ),
      );
    }

    if (response == null && error != null) {
      return _InfoCard(
        child: Text(error),
      );
    }

    if (response == null) {
      return const _InfoCard(
        child: Text('Choose a site, zone, and date range, then load the frost timeline.'),
      );
    }

    if (response.points.isEmpty) {
      return const _InfoCard(
        child: Text('No frost timeline data available in this range.'),
      );
    }

    final dateRange = appState.frostTimelineDateRange ??
        PickerDateRange(
          DateTime.now().subtract(const Duration(days: 2)),
          DateTime.now(),
        );
    final axisConfig = _getAxisConfig(dateRange);
    final now = DateTime.now();
    final visibleStart = dateRange.startDate ?? now.subtract(const Duration(days: 2));
    final visibleEnd = dateRange.endDate ?? now;

    final shiftedChancePoints = _buildShiftedChancePoints(
      response.points,
      visibleStart,
      visibleEnd.add(_forecastWindow),
    );

    final splitChancePoints = _splitShiftedChancePointsAtNow(
      shiftedChancePoints,
      now,
    );

    final shouldExtendForFutureForecast =
        !visibleEnd.isBefore(now.subtract(_forecastWindow));

    final shiftedAxisEnd =
        shiftedChancePoints.isNotEmpty ? shiftedChancePoints.last.time : visibleEnd;

    final axisMaximum = shouldExtendForFutureForecast &&
            shiftedAxisEnd.isAfter(visibleEnd)
        ? shiftedAxisEnd
        : visibleEnd;
    final chartHeight = viewportInfo.isDesktop
        ? 430.0
        : viewportInfo.isMobileLandscape
            ? 300.0
            : 260.0;

    final temperaturePoints = response.points
        .where(
          (p) =>
              p.temperature != null &&
              !p.time.isBefore(visibleStart) &&
              !p.time.isAfter(visibleEnd),
        )
        .toList();

    final humidityPoints = response.points
        .where(
          (p) =>
              p.humidity != null &&
              !p.time.isBefore(visibleStart) &&
              !p.time.isAfter(visibleEnd),
        )
        .toList();

    final soilTempPoints = response.points
        .where(
          (p) =>
              p.soilTemperature != null &&
              !p.time.isBefore(visibleStart) &&
              !p.time.isAfter(visibleEnd),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(),
          ),
        Text(
          'Interval: ${response.interval}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(error),
          ),
        const SizedBox(height: 12),
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
                if (index == null || _trackballDismissedByOutsideTap) return;
                Future<void>.delayed(Duration.zero, () {
                  if (!mounted || _trackballDismissedByOutsideTap) return;
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

                  final time = _trackballTimeForSeriesPoint(
                    seriesIndex: seriesIndex,
                    pointIndex: pointIndex,
                    temperaturePoints: temperaturePoints,
                    humidityPoints: humidityPoints,
                    soilTempPoints: soilTempPoints,
                    solidChancePoints: splitChancePoints.solid,
                    dashedChancePoints: splitChancePoints.dashed,
                  );

                  if (time != null) {
                    args.chartPointInfo.header = _trackballHeaderFormat.format(time);
                  }
                },
                legend: const Legend(
                  isVisible: true,
                  position: LegendPosition.bottom,
                  overflowMode: LegendItemOverflowMode.wrap,
                ),
                trackballBehavior: _trackballBehavior,
                primaryXAxis: DateTimeAxis(
                  minimum: visibleStart,
                  maximum: axisMaximum,
                  edgeLabelPlacement: EdgeLabelPlacement.shift,
                  intervalType: axisConfig.intervalType,
                  interval: axisConfig.axisInterval,
                  axisLabelFormatter: (AxisLabelRenderDetails details) {
                    final dt = DateTime.fromMillisecondsSinceEpoch(details.value.toInt());
                    return ChartAxisLabel(
                      axisConfig.labelDateFormat.format(dt),
                      details.textStyle,
                    );
                  },
                ),
                primaryYAxis: const NumericAxis(
                  majorGridLines: MajorGridLines(width: 0.5),
                ),
                series: [
                  LineSeries<FrostTimelinePoint, DateTime>(
                    name: 'Temperature',
                    dataSource: temperaturePoints,
                    xValueMapper: (p, _) => p.time,
                    yValueMapper: (p, _) => p.temperature!,
                  ),
                  LineSeries<FrostTimelinePoint, DateTime>(
                    name: 'Humidity',
                    dataSource: humidityPoints,
                    xValueMapper: (p, _) => p.time,
                    yValueMapper: (p, _) => p.humidity!,
                  ),
                  LineSeries<FrostTimelinePoint, DateTime>(
                    name: 'Soil Temp',
                    dataSource: soilTempPoints,
                    xValueMapper: (p, _) => p.time,
                    yValueMapper: (p, _) => p.soilTemperature!,
                  ),
                  LineSeries<_ShiftedChancePoint, DateTime>(
                    name: 'Frost Chance (%) - next 6h',
                    color: _frostChanceColor,
                    dataSource: splitChancePoints.solid,
                    xValueMapper: (p, _) => p.time,
                    yValueMapper: (p, _) => p.value,
                    width: 2.5,
                  ),
                  LineSeries<_ShiftedChancePoint, DateTime>(
                    name: 'Frost Chance (%) - next 6h (Predicted)',
                    color: _frostChanceColor,
                    dataSource: splitChancePoints.dashed,
                    xValueMapper: (p, _) => p.time,
                    yValueMapper: (p, _) => p.value,
                    width: 2.5,
                    dashArray: const <double>[8, 4],
                    isVisibleInLegend: false,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

class _ShiftedChancePoint {
  const _ShiftedChancePoint({
    required this.sourceTime,
    required this.time,
    required this.value,
  });

  final DateTime sourceTime;
  final DateTime time;
  final double value;
}
