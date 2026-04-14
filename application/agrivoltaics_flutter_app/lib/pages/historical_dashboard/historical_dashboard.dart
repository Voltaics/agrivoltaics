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
import '../../responsive/app_viewport.dart';

class HistoricalDashboardPage extends StatefulWidget {
  const HistoricalDashboardPage({super.key});

  @override
  State<HistoricalDashboardPage> createState() => _HistoricalDashboardPageState();
}

class _HistoricalDashboardPageState extends State<HistoricalDashboardPage> {
  final ZoneService _zoneService = ZoneService();
  final SiteService _siteService = SiteService();
  late final HistoricalSeriesService _seriesService;

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
    
    // Initialize date range: exactly 2 days (48 hours) ago to now
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = context.read<AppState>();
      if (appState.historicalDateRange == null) {
        final now = DateTime.now();
        final twoDaysAgo = now.subtract(const Duration(days: 2));
        appState.setHistoricalDateRange(PickerDateRange(twoDaysAgo, now));
      }
    });
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
    final selectedSite = appState.historicalSelectedSite;
    final dateRange = appState.historicalDateRange ??
        PickerDateRange(
          DateTime.now().subtract(const Duration(days: 2)),
          DateTime.now(),
        );
    final selectedZoneIds = appState.historicalSelectedZoneIds;
    final selectedReadings = appState.historicalSelectedReadings;
    final selectedAggregation = appState.historicalSelectedAggregation;
    final historicalResponse = appState.historicalResponse;
    final historicalIsLoading = appState.historicalIsLoading;
    final historicalErrorMessage = appState.historicalErrorMessage;

    final viewportInfo = AppViewportInfo.fromMediaQuery(MediaQuery.of(context));

    if (selectedOrg == null) {
      if (viewportInfo.isDesktop) {
        return LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    HistoricalDashboardHeader(),
                    SizedBox(height: 12),
                    NoOrgPlaceholderWidget(),
                  ],
                ),
              ),
            );
          },
        );
      }

      return const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 8),
            HistoricalDashboardHeader(),
            NoOrgPlaceholderWidget(),
          ],
        ),
      );
    }

    if (viewportInfo.isDesktop) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const HistoricalDashboardHeader(),
                  StreamBuilder<List<models.Site>>(
              stream: _getSiteStream(selectedOrg.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text('Error loading sites: ${snapshot.error}'),
                    ),
                  );
                }

                final sites = snapshot.data ?? [];

                return SiteSelectorWidget(
                  orgId: selectedOrg.id,
                  sites: sites,
                  selectedSite: selectedSite,
                  dateRange: dateRange,
                  onSiteChanged: (site) {
                    appState.setHistoricalSelectedSite(site);
                    appState.setHistoricalSelectedZoneIds(<String>{});
                    appState.setHistoricalSelectedReadings(<String>{});
                    appState.clearHistoricalResults();
                  },
                  onDateRangePressed: () {
                    showDateRangePickerDialog(
                      context,
                      initialRange: dateRange,
                      onApplied: (range) {
                        appState.setHistoricalDateRange(range);
                        _applyFilters(newDateRange: range);
                      },
                    );
                  },
                  isLoading: false,
                );
              },
            ),
                  const SizedBox(height: 12),
                  if (selectedSite != null)
                    ZoneSectionWidget(
                orgId: selectedOrg.id,
                selectedSite: selectedSite,
                zoneStream: _getZoneStream(selectedOrg.id, selectedSite.id),
                selectedZoneIds: selectedZoneIds,
                selectedReadings: selectedReadings,
                selectedAggregation: selectedAggregation,
                onApplyFilters: _applyFilters,
                onZoneSelected: (zoneId, selected) {
                  final next = Set<String>.from(appState.historicalSelectedZoneIds);
                  if (selected) {
                    next.add(zoneId);
                  } else {
                    next.remove(zoneId);
                  }
                  appState.setHistoricalSelectedZoneIds(next);
                },
                onReadingSelected: (reading, selected) {
                  final next = Set<String>.from(appState.historicalSelectedReadings);
                  if (selected) {
                    next.add(reading);
                  } else {
                    next.remove(reading);
                  }
                  appState.setHistoricalSelectedReadings(next);
                },
                onAggregationChanged: (agg) {
                  appState.setHistoricalSelectedAggregation(agg);
                },
                onZonesLoaded: _syncSelections,
                availableReadings: _availableReadings,
                response: historicalResponse,
                isLoading: historicalIsLoading,
                errorMessage: historicalErrorMessage,
                isDesktop: viewportInfo.isDesktop,
                isMobileLandscape: viewportInfo.isMobileLandscape,
                dateRange: dateRange,
              )
                  else
                    const NoSitePlaceholderWidget(),
                ],
              ),
            ),
          );
        },
      );
    }

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HistoricalDashboardHeader(),
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
                selectedSite: selectedSite,
                dateRange: dateRange,
                onSiteChanged: (site) {
                  appState.setHistoricalSelectedSite(site);
                  appState.setHistoricalSelectedZoneIds(<String>{});
                  appState.setHistoricalSelectedReadings(<String>{});
                  appState.clearHistoricalResults();
                },
                onDateRangePressed: () {
                  showDateRangePickerDialog(
                    context,
                    initialRange: dateRange,
                    onApplied: (range) {
                      appState.setHistoricalDateRange(range);
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
              selectedZoneIds: selectedZoneIds,
              selectedReadings: selectedReadings,
              selectedAggregation: selectedAggregation,
              onApplyFilters: _applyFilters,
              onZoneSelected: (zoneId, selected) {
                final next = Set<String>.from(appState.historicalSelectedZoneIds);
                if (selected) {
                  next.add(zoneId);
                } else {
                  next.remove(zoneId);
                }
                appState.setHistoricalSelectedZoneIds(next);
              },
              onReadingSelected: (reading, selected) {
                final next = Set<String>.from(appState.historicalSelectedReadings);
                if (selected) {
                  next.add(reading);
                } else {
                  next.remove(reading);
                }
                appState.setHistoricalSelectedReadings(next);
              },
              onAggregationChanged: (agg) {
                appState.setHistoricalSelectedAggregation(agg);
              },
              onZonesLoaded: _syncSelections,
              availableReadings: _availableReadings,
              response: historicalResponse,
              isLoading: historicalIsLoading,
              errorMessage: historicalErrorMessage,
              isDesktop: viewportInfo.isDesktop,
              isMobileLandscape: viewportInfo.isMobileLandscape,
              dateRange: dateRange,
            )
          else
            const NoSitePlaceholderWidget(),
        ],
      ),
    );
  }

  void _syncSelections(List<Zone> zones) {
    final appState = context.read<AppState>();

    final availableZoneIds = zones
        .where((zone) => zone.zoneChecked)
        .map((zone) => zone.id)
        .toSet();

    final nextZoneIds = Set<String>.from(appState.historicalSelectedZoneIds);
    if (nextZoneIds.isEmpty) {
      nextZoneIds.addAll(availableZoneIds);
    } else {
      nextZoneIds.removeWhere((id) => !availableZoneIds.contains(id));
      if (nextZoneIds.isEmpty) {
        nextZoneIds.addAll(availableZoneIds);
      }
    }
    appState.setHistoricalSelectedZoneIds(nextZoneIds);

    final availableReadings = _availableReadings(zones);
    final nextReadings = Set<String>.from(appState.historicalSelectedReadings);
    if (nextReadings.isEmpty) {
      nextReadings.addAll(availableReadings);
    } else {
      nextReadings.removeWhere((reading) => !availableReadings.contains(reading));
      if (nextReadings.isEmpty) {
        nextReadings.addAll(availableReadings);
      }
    }
    appState.setHistoricalSelectedReadings(nextReadings);
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
    _applyFiltersAsync(newDateRange: newDateRange);
  }

  Future<void> _applyFiltersAsync({PickerDateRange? newDateRange}) async {
    final appState = context.read<AppState>();
    final selectedOrg = appState.selectedOrganization;
    final selectedSite = appState.historicalSelectedSite;
    final selectedZoneIds = appState.historicalSelectedZoneIds;
    final selectedReadings = appState.historicalSelectedReadings;
    final selectedAggregation = appState.historicalSelectedAggregation;

    if (selectedOrg == null || selectedSite == null) {
      return;
    }

    if (selectedZoneIds.isEmpty || selectedReadings.isEmpty) {
      appState.setHistoricalError('Select at least one zone and reading.');
      return;
    }

    final effectiveRange = newDateRange ?? appState.historicalDateRange;
    if (effectiveRange == null ||
        effectiveRange.startDate == null ||
        effectiveRange.endDate == null) {
      appState.setHistoricalError('Select a valid date range.');
      return;
    }

    final start = effectiveRange.startDate!;
    final end = effectiveRange.endDate!;

    if (newDateRange != null) {
      appState.setHistoricalDateRange(newDateRange);
    }

    appState.startHistoricalLoad();

    try {
      final response = await _fetchHistoricalSeries(
        organizationId: selectedOrg.id,
        siteId: selectedSite.id,
        zoneIds: selectedZoneIds.toList(),
        readings: selectedReadings.toList(),
        start: start,
        end: end,
        timezone: selectedSite.timezone,
        aggregation: selectedAggregation,
      );

      if (!mounted) return;
      appState.setHistoricalResponse(response);
    } catch (e) {
      if (!mounted) return;
      appState.setHistoricalError('Failed to load data: $e');
    }
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
}
