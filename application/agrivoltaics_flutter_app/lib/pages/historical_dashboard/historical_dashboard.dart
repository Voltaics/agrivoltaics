import 'package:agrivoltaics_flutter_app/app_constants.dart';
import 'package:agrivoltaics_flutter_app/models/zone.dart';
import 'package:agrivoltaics_flutter_app/models/site.dart' as models;
import 'package:agrivoltaics_flutter_app/pages/home/site_zone_breadcrumb.dart';
import 'package:agrivoltaics_flutter_app/services/historical_series_service.dart';
import 'package:agrivoltaics_flutter_app/services/zone_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';

import '../../app_state.dart';

class HistoricalDashboardPage extends StatefulWidget {
  const HistoricalDashboardPage({super.key});

  @override
  State<HistoricalDashboardPage> createState() => _HistoricalDashboardPageState();
}

class _HistoricalDashboardPageState extends State<HistoricalDashboardPage> {
  final ZoneService _zoneService = ZoneService();
  late final HistoricalSeriesService _seriesService;

  String? _lastSiteId;
  models.Site? _selectedSite;

  PickerDateRange _dateRange = PickerDateRange(
    DateTime.now().subtract(const Duration(days: 7)),
    DateTime.now(),
  );

  final Set<String> _selectedZoneIds = <String>{};
  final Set<String> _selectedReadings = <String>{};

  Future<HistoricalResponse>? _futureResponse;
  String? _errorMessage;

  static const Map<String, String> _readingLabels = {
    'temperature': 'Temperature',
    'humidity': 'Humidity',
    'light': 'Light',
    'rain': 'Rain',
    'frost': 'Frost',
    'soil': 'Soil',
    'rssi': 'Signal',
  };

  @override
  void initState() {
    super.initState();
    _seriesService = HistoricalSeriesService(
      endpointUrl: AppConstants.historicalSeriesEndpoint,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = context.read<AppState>();
    _selectedSite ??= appState.selectedSite;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final selectedOrg = appState.selectedOrganization;
    final selectedSite = _selectedSite;

    _refreshOnSiteChange(selectedSite?.id);

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isWideScreen = screenWidth >= 1280 || screenHeight < screenWidth;

    if (selectedOrg == null || selectedSite == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Historical Trends',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'Review sensor trends over time with custom filters.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.location_off,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      selectedOrg == null ? 'No organization selected' : 'No sites available',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      selectedOrg == null
                          ? 'Select an organization from the menu to get started'
                          : 'Create a site or select a different organization',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Historical Trends',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
                'Review sensor trends over time with custom filters.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
        SiteZoneBreadcrumb(
          showZoneSelector: false,
          selectedSite: selectedSite,
          onSiteSelected: (site) {
            setState(() {
              _selectedSite = site;
            });
          },
        ),
        Expanded(
          child: StreamBuilder<List<Zone>>(
            stream: _zoneService.getZones(selectedOrg.id, selectedSite.id),
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
               _syncSelections(zones);

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFilterCard(
                      context,
                      zones: zones,
                      isWideScreen: isWideScreen,
                    ),
                    const SizedBox(height: 16),
                    _buildResultsSection(
                      zoneLookup: {
                        for (final zone in zones) zone.id: zone.name,
                      },
                      isWideScreen: isWideScreen,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _syncSelections(List<Zone> zones) {
    final availableZoneIds = zones.where((zone) => zone.zoneChecked).map((zone) => zone.id).toSet();

    if (_selectedZoneIds.isEmpty) {
      _selectedZoneIds.addAll(availableZoneIds);
    } else {
      _selectedZoneIds.removeWhere((id) => !availableZoneIds.contains(id));
      if (_selectedZoneIds.isEmpty) {
        _selectedZoneIds.addAll(availableZoneIds);
      }
    }

    final availableReadings = _availableReadings(zones);
    if (_selectedReadings.isEmpty) {
      _selectedReadings.addAll(availableReadings);
    } else {
      _selectedReadings.removeWhere((reading) => !availableReadings.contains(reading));
      if (_selectedReadings.isEmpty) {
        _selectedReadings.addAll(availableReadings);
      }
    }
  }

  Set<String> _availableReadings(List<Zone> zones) {
    final readings = <String>{};

    for (final zone in zones) {
      readings.addAll(zone.readings.keys);
    }

    if (readings.isEmpty) {
      readings.addAll(_readingLabels.keys);
    }

    return readings;
  }

  Widget _buildFilterCard(
    BuildContext context, {
    required List<Zone> zones,
    required bool isWideScreen,
  }) {
    final dateFormat = DateFormat('MMM d, yyyy');
    final start = _dateRange.startDate ?? DateTime.now();
    final end = _dateRange.endDate ?? start;

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
                  onPressed: _applyFilters,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Apply'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: Text('${dateFormat.format(start)} - ${dateFormat.format(end)}'),
                  avatar: const Icon(Icons.date_range, size: 18),
                  onPressed: () => _showDateRangePicker(context),
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
                      final isSelected = _selectedZoneIds.contains(zone.id);
                      return FilterChip(
                        label: Text(zone.name),
                        selected: isSelected,
                        onSelected: (value) {
                          setState(() {
                            if (value) {
                              _selectedZoneIds.add(zone.id);
                            } else {
                              _selectedZoneIds.remove(zone.id);
                            }
                          });
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
               children: _availableReadings(zones).map((reading) {
                final isSelected = _selectedReadings.contains(reading);
                return FilterChip(
                  label: Text(_readingLabels[reading] ?? reading),
                  selected: isSelected,
                  onSelected: (value) {
                    setState(() {
                      if (value) {
                        _selectedReadings.add(reading);
                      } else {
                        _selectedReadings.remove(reading);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsSection({
    required Map<String, String> zoneLookup,
    required bool isWideScreen,
  }) {
    if (_selectedZoneIds.isEmpty || _selectedReadings.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 24),
        child: Center(
          child: Text('Select at least one zone and reading to load data.'),
        ),
      );
    }

    if (_futureResponse == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 24),
        child: Center(
          child: Text('Tap Apply to load historical data.'),
        ),
      );
    }

    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Center(
          child: Text(_errorMessage!),
        ),
      );
    }

    return FutureBuilder<HistoricalResponse>(
      future: _futureResponse,
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
              return _buildGraphCard(
                graph,
                zoneLookup: zoneLookup,
                isWideScreen: isWideScreen,
              );
            }).toList(),
          ],
        );
      },
    );
  }

  Widget _buildGraphCard(
    HistoricalGraph graph, {
    required Map<String, String> zoneLookup,
    required bool isWideScreen,
  }) {
    final title = _readingLabels[graph.field] ?? graph.field;
    final unit = graph.unit != null && graph.unit!.isNotEmpty
        ? ' (${graph.unit})'
        : '';

    final hasData = graph.series.any((series) => series.points.isNotEmpty);

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
                    edgeLabelPlacement: EdgeLabelPlacement.shift,
                    dateFormat: DateFormat('MM/dd'),
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
                    tooltipSettings: const InteractiveTooltip(
                      format: 'point.y',
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

  Future<void> _applyFilters() async {
    final appState = context.read<AppState>();
    final selectedOrg = appState.selectedOrganization;
    final selectedSite = appState.selectedSite;

    if (selectedOrg == null || selectedSite == null) {
      return;
    }

    if (_selectedZoneIds.isEmpty || _selectedReadings.isEmpty) {
      setState(() {
        _errorMessage = 'Select at least one zone and reading.';
      });
      return;
    }

    final start = _dateRange.startDate ?? DateTime.now().subtract(const Duration(days: 7));
    final end = _dateRange.endDate ?? DateTime.now();

    setState(() {
      _errorMessage = null;
      _futureResponse = _fetchHistoricalSeries(
        organizationId: selectedOrg.id,
        siteId: selectedSite.id,
        zoneIds: _selectedZoneIds.toList(),
        readings: _selectedReadings.toList(),
        start: start,
        end: end,
      );
    });
  }

  Future<HistoricalResponse> _fetchHistoricalSeries({
    required String organizationId,
    required String siteId,
    required List<String> zoneIds,
    required List<String> readings,
    required DateTime start,
    required DateTime end,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final idToken = user != null ? await user.getIdToken() : null;

    return _seriesService.fetchSeries(
      organizationId: organizationId,
      siteId: siteId,
      zoneIds: zoneIds,
      readings: readings,
      start: start,
      end: end,
      idToken: idToken,
    );
  }

  void _refreshOnSiteChange(String? siteId) {
    if (_lastSiteId == siteId) {
      return;
    }

    _lastSiteId = siteId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      setState(() {
        _futureResponse = null;
        _errorMessage = null;
      });

      if (siteId != null) {
        _applyFilters();
      }
    });
  }

  void _showDateRangePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        PickerDateRange tempRange = _dateRange;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text(
                    'Select date range',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 1),
              SizedBox(
                height: 360,
                child: SfDateRangePicker(
                  selectionMode: DateRangePickerSelectionMode.range,
                  initialSelectedRange: _dateRange,
                  maxDate: DateTime.now(),
                  onSelectionChanged: (args) {
                    if (args.value is PickerDateRange) {
                      tempRange = args.value;
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _dateRange = tempRange;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Apply range'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
