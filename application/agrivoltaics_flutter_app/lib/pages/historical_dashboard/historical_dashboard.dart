import 'package:agrivoltaics_flutter_app/app_constants.dart';
import 'package:agrivoltaics_flutter_app/models/zone.dart';
import 'package:agrivoltaics_flutter_app/models/site.dart' as models;
import 'package:agrivoltaics_flutter_app/services/historical_series_service.dart';
import 'package:agrivoltaics_flutter_app/services/zone_service.dart';
import 'package:agrivoltaics_flutter_app/services/site_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';

import '../../app_state.dart';
import 'dialogs/date_range_picker_dialog.dart';
import 'widgets/filter_card.dart';
import 'widgets/results_section.dart';
import 'widgets/site_selector.dart';

class HistoricalDashboardPage extends StatefulWidget {
  const HistoricalDashboardPage({super.key});

  @override
  State<HistoricalDashboardPage> createState() => _HistoricalDashboardPageState();
}

class _HistoricalDashboardPageState extends State<HistoricalDashboardPage> {
  final ZoneService _zoneService = ZoneService();
  final SiteService _siteService = SiteService();
  late final HistoricalSeriesService _seriesService;

  String? _lastSiteId;
  models.Site? _selectedSite;
  String? _lastSyncedSiteId;

  late PickerDateRange _dateRange;

  final Set<String> _selectedZoneIds = <String>{};
  final Set<String> _selectedReadings = <String>{};
  String _selectedAggregation = 'avg';

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
    
    // Initialize date range: exactly 7 days (168 hours) ago to now
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    _dateRange = PickerDateRange(sevenDaysAgo, now);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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

    if (selectedOrg == null) {
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
                    const Text(
                      'No organization selected',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Select an organization from the menu to get started',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
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
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StreamBuilder<List<models.Site>>(
                  stream: _siteService.getSites(selectedOrg.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text('Error loading sites: ${snapshot.error}'),
                      );
                    }

                    final sites = snapshot.data ?? [];

                    return SiteSelectorWidget(
                      orgId: selectedOrg.id,
                      sites: sites,
                      selectedSite: _selectedSite,
                      dateRange: _dateRange,
                      onSiteChanged: (site) {
                        setState(() {
                          _selectedSite = site;
                          _lastSyncedSiteId = null;
                          _selectedZoneIds.clear();
                          _selectedReadings.clear();
                        });
                      },
                      onDateRangePressed: () {
                        showDateRangePickerDialog(
                          context,
                          initialRange: _dateRange,
                          onApplied: (range) {
                            setState(() {
                              _dateRange = range;
                            });
                            _applyFilters();
                          },
                        );
                      },
                      isLoading: false,
                    );
                  },
                ),
                const SizedBox(height: 16),
                if (selectedSite != null) ...[
                  StreamBuilder<List<Zone>>(
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
                      
                      // Only sync selections when site changes
                      if (_lastSyncedSiteId != selectedSite.id) {
                        _lastSyncedSiteId = selectedSite.id;
                        _syncSelections(zones);
                        // Auto-query after syncing zones for new site
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            _applyFilters();
                          }
                        });
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FilterCardWidget(
                            zones: zones,
                            selectedZoneIds: _selectedZoneIds,
                            selectedReadings: _selectedReadings,
                            onApplyFilters: _applyFilters,
                            onZoneSelected: (zoneId, selected) {
                              setState(() {
                                if (selected) {
                                  _selectedZoneIds.add(zoneId);
                                } else {
                                  _selectedZoneIds.remove(zoneId);
                                }
                              });
                            },
                            onReadingSelected: (reading, selected) {
                              setState(() {
                                if (selected) {
                                  _selectedReadings.add(reading);
                                } else {
                                  _selectedReadings.remove(reading);
                                }
                              });
                            },
                            availableReadings: _availableReadings(zones),
                            selectedAggregation: _selectedAggregation,
                            onAggregationChanged: (agg) {
                              setState(() {
                                _selectedAggregation = agg;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          ResultsSectionWidget(
                            futureResponse: _futureResponse,
                            errorMessage: _errorMessage,
                            selectedZoneIds: _selectedZoneIds,
                            selectedReadings: _selectedReadings,
                            zoneLookup: {
                              for (final zone in zones) zone.id: zone.name,
                            },
                            isWideScreen: isWideScreen,
                            dateRange: _dateRange,
                          ),
                        ],
                      );
                    },
                  ),
                ] else ...[
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.business,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Select a site to view data',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
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

  Future<void> _applyFilters() async {
    final appState = context.read<AppState>();
    final selectedOrg = appState.selectedOrganization;
    final selectedSite = _selectedSite;

    if (selectedOrg == null || selectedSite == null) {
      return;
    }

    if (_selectedZoneIds.isEmpty || _selectedReadings.isEmpty) {
      setState(() {
        _errorMessage = 'Select at least one zone and reading.';
      });
      return;
    }

    // Use date range or fallback to 7 days ago (normalized)
    final DateTime start;
    final DateTime end;
    
    if (_dateRange.startDate != null && _dateRange.endDate != null) {
      start = _dateRange.startDate!;
      end = _dateRange.endDate!;
    } else {
      // Fallback: 7 days ago at 00:00:00 to now
      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7));
      start = DateTime(sevenDaysAgo.year, sevenDaysAgo.month, sevenDaysAgo.day);
      end = now;
    }

    setState(() {
      _errorMessage = null;
      _futureResponse = _fetchHistoricalSeries(
        organizationId: selectedOrg.id,
        siteId: selectedSite.id,
        zoneIds: _selectedZoneIds.toList(),
        readings: _selectedReadings.toList(),
        start: start,
        end: end,
        timezone: selectedSite.timezone,
        aggregation: _selectedAggregation,
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
    required String timezone,
    required String aggregation,
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
      timezone: timezone,
      aggregation: aggregation,
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
}
