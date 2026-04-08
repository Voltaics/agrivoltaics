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

enum _LoadState { idle, loading, success, error }

class FrostPredictionTimelineModel extends StatefulWidget {
  const FrostPredictionTimelineModel({super.key});

  @override
  State<FrostPredictionTimelineModel> createState() => _FrostPredictionTimelineModelState();
}

class _FrostPredictionTimelineModelState extends State<FrostPredictionTimelineModel> {
  final SiteService _siteService = SiteService();
  final ZoneService _zoneService = ZoneService();
  late final FrostPredictionSeriesService _service;

  models.Site? _selectedSite;
  Zone? _selectedZone;
  PickerDateRange? _dateRange;
  Stream<List<Zone>>? _zoneStream;
  String? _zoneStreamSiteId;

  _LoadState _state = _LoadState.idle;
  String? _error;
  FrostTimelineResponse? _response;

  late final TrackballBehavior _trackballBehavior;
  int? _lastSelectedDataPointIndex;
  bool _trackballDismissedByOutsideTap = false;

  @override
  void initState() {
    super.initState();
    _service = FrostPredictionSeriesService(
      endpointUrl: AppConstants.frostPredictionSeriesEndpoint,
    );

    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    _dateRange = PickerDateRange(sevenDaysAgo, now);

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

    if (org == null) {
      setState(() {
        _state = _LoadState.error;
        _error = 'Select an organization first.';
      });
      return;
    }

    if (_selectedSite == null) {
      setState(() {
        _state = _LoadState.error;
        _error = 'Select a site.';
      });
      return;
    }

    if (_selectedZone == null) {
      setState(() {
        _state = _LoadState.error;
        _error = 'Select a zone.';
      });
      return;
    }

    final start = _dateRange?.startDate;
    final end = _dateRange?.endDate;

    if (start == null || end == null) {
      setState(() {
        _state = _LoadState.error;
        _error = 'Select a valid date range.';
      });
      return;
    }

    setState(() {
      _state = _LoadState.loading;
      _error = null;
      _response = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      final idToken = user != null ? await user.getIdToken() : null;

      final response = await _service.fetchTimeline(
        organizationId: org.id,
        siteId: _selectedSite!.id,
        zoneId: _selectedZone!.id,
        start: start,
        end: end,
        timezone: _selectedSite!.timezone,
        idToken: idToken,
      );

      if (!mounted) return;

      setState(() {
        _state = _LoadState.success;
        _response = response;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _state = _LoadState.error;
        _error = e.toString();
      });
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedSite?.id,
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
            setState(() {
              _selectedSite = site;
              _selectedZone = null;
              _response = null;
              _state = _LoadState.idle;
              _error = null;
              _zoneStream = null;
              _zoneStreamSiteId = null;
            });
          },
        ),
        const SizedBox(height: 12),
        if (_selectedSite == null)
          const Text('Choose a site to load zones.')
        else
          StreamBuilder<List<Zone>>(
            stream: _getZoneStream(orgId, _selectedSite!.id),
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

              final selectedZoneStillExists = zones.any((z) => z.id == _selectedZone?.id);
              if (!selectedZoneStillExists && _selectedZone != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() {
                    _selectedZone = null;
                  });
                });
              }

              return DropdownButtonFormField<String>(
                initialValue: selectedZoneStillExists ? _selectedZone?.id : null,
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
                  setState(() {
                    _selectedZone = zone;
                    _response = null;
                    _state = _LoadState.idle;
                    _error = null;
                  });
                },
              );
            },
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () {
            showDateRangePickerDialog(
              context,
              initialRange: _dateRange ?? PickerDateRange(DateTime.now(), DateTime.now()),
              onApplied: (range) {
                setState(() {
                  _dateRange = range;
                  _response = null;
                  _state = _LoadState.idle;
                  _error = null;
                });
              },
            );
          },
          icon: const Icon(Icons.date_range),
          label: Text(_formatRange(_dateRange!)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _state == _LoadState.loading ? null : _loadTimeline,
            icon: const Icon(Icons.show_chart),
            label: const Text('Load frost timeline'),
          ),
        ),
      ],
    );
  }

  Widget _buildResults(BuildContext context, AppViewportInfo viewportInfo) {
    switch (_state) {
      case _LoadState.idle:
        return const _InfoCard(
          child: Text('Choose a site, zone, and date range, then load the frost timeline.'),
        );
      case _LoadState.loading:
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
      case _LoadState.error:
        return _InfoCard(
          child: Text(_error ?? 'Unknown error'),
        );
      case _LoadState.success:
        final response = _response;
        if (response == null || response.points.isEmpty) {
          return const _InfoCard(
            child: Text('No frost timeline data available in this range.'),
          );
        }

        final dateRange = _dateRange!;
        final axisConfig = _getAxisConfig(dateRange);
        final chartHeight = viewportInfo.isDesktop
            ? 430.0
            : viewportInfo.isMobileLandscape
                ? 300.0
                : 260.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Interval: ${response.interval}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
                      if (pointIndex != null) {
                        _trackballDismissedByOutsideTap = false;
                        _lastSelectedDataPointIndex = pointIndex;
                      }
                    },
                    legend: const Legend(
                      isVisible: true,
                      position: LegendPosition.bottom,
                      overflowMode: LegendItemOverflowMode.wrap,
                    ),
                    trackballBehavior: _trackballBehavior,
                    primaryXAxis: DateTimeAxis(
                      minimum: dateRange.startDate,
                      maximum: dateRange.endDate,
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
                        dataSource: response.points.where((p) => p.temperature != null).toList(),
                        xValueMapper: (p, _) => p.time,
                        yValueMapper: (p, _) => p.temperature!,
                      ),
                      LineSeries<FrostTimelinePoint, DateTime>(
                        name: 'Humidity',
                        dataSource: response.points.where((p) => p.humidity != null).toList(),
                        xValueMapper: (p, _) => p.time,
                        yValueMapper: (p, _) => p.humidity!,
                      ),
                      LineSeries<FrostTimelinePoint, DateTime>(
                        name: 'Soil Temp',
                        dataSource: response.points.where((p) => p.soilTemperature != null).toList(),
                        xValueMapper: (p, _) => p.time,
                        yValueMapper: (p, _) => p.soilTemperature!,
                      ),
                      LineSeries<FrostTimelinePoint, DateTime>(
                        name: 'Frost Chance (%)',
                        dataSource: response.points,
                        xValueMapper: (p, _) => p.time,
                        yValueMapper: (p, _) => p.predictedChance,
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