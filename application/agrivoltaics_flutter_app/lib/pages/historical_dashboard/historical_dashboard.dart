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
import 'widgets/no_org_placeholder.dart';
import 'widgets/no_site_placeholder.dart';
import 'widgets/page_header.dart';
import 'widgets/site_selector.dart';
import 'widgets/zone_section.dart';

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
  String? _lastOrgId;
  models.Site? _selectedSite;

  late PickerDateRange _dateRange;
  final ScrollController _scrollController = ScrollController();

  // Cached zone stream — only recreated when the site changes so that
  // filter setState calls don't tear down and recreate the Firestore listener.
  Stream<List<Zone>>? _zoneStream;
  String? _zoneStreamSiteId;

  Stream<List<Zone>> _getZoneStream(String orgId, String siteId) {
    if (_zoneStream == null || _zoneStreamSiteId != siteId) {
      _zoneStream = _zoneService.getZones(orgId, siteId);
      _zoneStreamSiteId = siteId;
    }
    return _zoneStream!;
  }

  // Cached site stream — only recreated when the org changes.
  Stream<List<models.Site>>? _siteStream;
  String? _siteStreamOrgId;

  Stream<List<models.Site>> _getSiteStream(String orgId) {
    if (_siteStream == null || _siteStreamOrgId != orgId) {
      _siteStream = _siteService.getSites(orgId);
      _siteStreamOrgId = orgId;
    }
    return _siteStream!;
  }

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
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final selectedOrg = appState.selectedOrganization;
    final selectedSite = _selectedSite;

    _refreshOnOrgChange(selectedOrg?.id);
    _refreshOnSiteChange(selectedSite?.id);

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isWideScreen = screenWidth >= 1280 || screenHeight < screenWidth;

    if (selectedOrg == null) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 8),
          HistoricalDashboardHeader(),
          NoOrgPlaceholderWidget(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const HistoricalDashboardHeader(),
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StreamBuilder<List<models.Site>>(
                  stream: _getSiteStream(selectedOrg.id),
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
                          _selectedZoneIds.clear();
                          _selectedReadings.clear();
                        });
                      },
                      onDateRangePressed: () {
                        showDateRangePickerDialog(
                          context,
                          initialRange: _dateRange,
                          onApplied: (range) {
                            _applyFilters(newDateRange: range);
                          },
                        );
                      },
                      isLoading: false,
                    );
                  },
                ),
                const SizedBox(height: 16),
                if (selectedSite != null)
                  ZoneSectionWidget(
                    orgId: selectedOrg.id,
                    selectedSite: selectedSite,
                    zoneStream: _getZoneStream(selectedOrg.id, selectedSite.id),
                    selectedZoneIds: _selectedZoneIds,
                    selectedReadings: _selectedReadings,
                    selectedAggregation: _selectedAggregation,
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
                    onAggregationChanged: (agg) {
                      setState(() {
                        _selectedAggregation = agg;
                      });
                    },
                    onZonesLoaded: _syncSelections,
                    availableReadings: _availableReadings,
                    futureResponse: _futureResponse,
                    errorMessage: _errorMessage,
                    isWideScreen: isWideScreen,
                    dateRange: _dateRange,
                  )
                else
                  const NoSitePlaceholderWidget(),
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

  void _applyFilters({PickerDateRange? newDateRange}) {
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

    // Use the incoming range if provided, otherwise fall back to current state.
    final effectiveRange = newDateRange ?? _dateRange;
    final DateTime start;
    final DateTime end;
    
    if (effectiveRange.startDate != null && effectiveRange.endDate != null) {
      start = effectiveRange.startDate!;
      end = effectiveRange.endDate!;
    } else {
      // Fallback: 7 days ago at 00:00:00 to now
      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7));
      start = DateTime(sevenDaysAgo.year, sevenDaysAgo.month, sevenDaysAgo.day);
      end = now;
    }

    // Single setState: _dateRange and _futureResponse always update together
    // so there is never a frame where axis config and data are mismatched.
    setState(() {
      if (newDateRange != null) _dateRange = newDateRange;
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

  void _refreshOnOrgChange(String? orgId) {
    if (_lastOrgId == orgId) {
      return;
    }

    _lastOrgId = orgId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      setState(() {
        // Clear all org-scoped state so stale site/zone references
        // from the previous org can never reach Firestore or the chart.
        _selectedSite = null;
        _lastSiteId = null;
        _selectedZoneIds.clear();
        _selectedReadings.clear();
        _futureResponse = null;
        _errorMessage = null;
        // Invalidate cached streams so they rebuild under the new org.
        _siteStream = null;
        _siteStreamOrgId = null;
        _zoneStream = null;
        _zoneStreamSiteId = null;
      });
    });
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
