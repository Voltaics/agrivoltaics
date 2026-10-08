import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app_colors.dart';
import '../../../../app_state.dart';
import '../../../../models/frost_engine_state.dart';
import '../../../../models/site.dart' as models;
import '../../../../models/zone.dart';
import '../../../../services/frost_engine_state_service.dart';
import '../../../../services/site_service.dart';
import '../../../../services/zone_service.dart';
import 'config/frost_engine_config_dialog.dart';

class _LevelMeta {
  const _LevelMeta(this.label, this.color);
  final String label;
  final Color color;
}

const Map<String, _LevelMeta> _kLevelMeta = {
  'normal': _LevelMeta('Normal', AppColors.success),
  'watch': _LevelMeta('Frost Watch', AppColors.amber),
  'warning': _LevelMeta('Frost Warning', AppColors.warning),
  'imminent': _LevelMeta('Frost Imminent', Color(0xFFFF5722)),
  'event': _LevelMeta('Freeze Event in Progress', AppColors.error),
  'allClear': _LevelMeta('All Clear', AppColors.info),
};

const Map<String, String> _kSubWarningLabel = {
  'radiation': 'Radiation',
  'advective': 'Advective',
  'mixed': 'Mixed',
};

/// Zone-scoped frost-engine status card — the farmer-facing "what is the
/// frost engine seeing right now" panel (plan §3). Streams
/// `frostEngineState/current` directly via `FrostEngineStateService` and
/// renders the exact display fields from the professor's spec (`docs/
/// Updated_Frost_Alert_Rules.pdf`, "Web App Display and Implementation
/// Specification"): Air temperature / Dew point / Dew-point spread / Leaf
/// condition / Continuous wetness / Wind speed / Surface status.
///
/// Site/zone selection is local widget state (not routed through
/// `app_state.dart`) — per plan §3, no cross-page selection persistence was
/// called for here, unlike the frost prediction timeline's
/// `frostTimelineSelected*`.
class FrostAlertStateModel extends StatefulWidget {
  const FrostAlertStateModel({super.key});

  @override
  State<FrostAlertStateModel> createState() => _FrostAlertStateModelState();
}

class _FrostAlertStateModelState extends State<FrostAlertStateModel> {
  final SiteService _siteService = SiteService();
  final ZoneService _zoneService = ZoneService();
  final FrostEngineStateService _stateService = const FrostEngineStateService();

  Stream<List<Zone>>? _zoneStream;
  String? _zoneStreamSiteId;

  String? _selectedSiteId;
  String? _selectedZoneId;
  String? _selectedZoneName;

  Stream<List<Zone>> _getZoneStream(String orgId, String siteId) {
    if (_zoneStream == null || _zoneStreamSiteId != siteId) {
      _zoneStream = _zoneService.getZones(orgId, siteId);
      _zoneStreamSiteId = siteId;
    }
    return _zoneStream!;
  }

  Future<void> _showConfigDialog(BuildContext context, String orgId) async {
    final siteId = _selectedSiteId;
    final zoneId = _selectedZoneId;
    if (siteId == null || zoneId == null) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => FrostEngineConfigDialog(
        orgId: orgId,
        siteId: siteId,
        zoneId: zoneId,
        zoneName: _selectedZoneName,
      ),
    );

    if (!mounted || saved != true) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Frost engine rules saved.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final selectedOrg = appState.selectedOrganization;

    if (selectedOrg == null) {
      return const _FrostAlertCard(
        child: Text('Select an organization to view frost alert status.'),
      );
    }

    return StreamBuilder<List<models.Site>>(
      stream: _siteService.getSites(selectedOrg.id),
      builder: (context, siteSnapshot) {
        if (siteSnapshot.connectionState == ConnectionState.waiting) {
          return const _FrostAlertCard(
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (siteSnapshot.hasError) {
          return _FrostAlertCard(
            child: Text('Error loading sites: ${siteSnapshot.error}'),
          );
        }

        final sites = siteSnapshot.data ?? [];

        return _FrostAlertCard(
          headerActions: [
            IconButton(
              tooltip: 'Frost engine rules',
              icon: const Icon(Icons.settings),
              onPressed: _selectedZoneId == null
                  ? null
                  : () => _showConfigDialog(context, selectedOrg.id),
            ),
          ],
          child: sites.isEmpty
              ? const Text('No sites found for this organization.')
              : _buildBody(context, sites, selectedOrg.id),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, List<models.Site> sites, String orgId) {
    final selectedSiteStillExists = sites.any((s) => s.id == _selectedSiteId);
    if (!selectedSiteStillExists && _selectedSiteId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _selectedSiteId = null;
          _selectedZoneId = null;
          _selectedZoneName = null;
        });
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: selectedSiteStillExists ? _selectedSiteId : null,
                decoration: const InputDecoration(
                  labelText: 'Site',
                  border: OutlineInputBorder(),
                ),
                items: sites
                    .map((site) => DropdownMenuItem(value: site.id, child: Text(site.name)))
                    .toList(),
                onChanged: (siteId) {
                  setState(() {
                    _selectedSiteId = siteId;
                    _selectedZoneId = null;
                    _selectedZoneName = null;
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _selectedSiteId == null
                  ? const InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Zone',
                        border: OutlineInputBorder(),
                      ),
                      child: Text('Choose a site first'),
                    )
                  : _buildZoneDropdown(orgId, _selectedSiteId!),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_selectedZoneId == null)
          const Text('Choose a site and zone to view frost alert status.')
        else
          StreamBuilder<FrostEngineState?>(
            stream: _stateService.streamState(
              orgId: orgId,
              siteId: _selectedSiteId!,
              zoneId: _selectedZoneId!,
            ),
            builder: (context, stateSnapshot) {
              if (stateSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (stateSnapshot.hasError) {
                return Text('Error loading frost engine state: ${stateSnapshot.error}');
              }

              final state = stateSnapshot.data;
              if (state == null) {
                return const Text(
                  'No frost engine data yet for this zone. Either the frost engine '
                  'is not enabled for this zone (see the gear icon), or it hasn\'t '
                  'evaluated its first tick yet.',
                );
              }

              return _FrostStatusDisplay(state: state);
            },
          ),
      ],
    );
  }

  Widget _buildZoneDropdown(String orgId, String siteId) {
    return StreamBuilder<List<Zone>>(
      stream: _getZoneStream(orgId, siteId),
      builder: (context, zoneSnapshot) {
        if (zoneSnapshot.connectionState == ConnectionState.waiting) {
          return const InputDecorator(
            decoration: InputDecoration(
              labelText: 'Zone',
              border: OutlineInputBorder(),
            ),
            child: SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        if (zoneSnapshot.hasError) {
          return Text('Error loading zones: ${zoneSnapshot.error}');
        }

        final zones = (zoneSnapshot.data ?? []).where((z) => z.zoneChecked).toList();

        if (zones.isEmpty) {
          return const InputDecorator(
            decoration: InputDecoration(
              labelText: 'Zone',
              border: OutlineInputBorder(),
            ),
            child: Text('No enabled zones'),
          );
        }

        final selectedZoneStillExists = zones.any((z) => z.id == _selectedZoneId);
        if (!selectedZoneStillExists && _selectedZoneId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _selectedZoneId = null;
              _selectedZoneName = null;
            });
          });
        }

        return DropdownButtonFormField<String>(
          initialValue: selectedZoneStillExists ? _selectedZoneId : null,
          decoration: const InputDecoration(
            labelText: 'Zone',
            border: OutlineInputBorder(),
          ),
          items: zones.map((z) => DropdownMenuItem(value: z.id, child: Text(z.name))).toList(),
          onChanged: (zoneId) {
            final zone = zones.where((z) => z.id == zoneId).firstOrNull;
            setState(() {
              _selectedZoneId = zoneId;
              _selectedZoneName = zone?.name;
            });
          },
        );
      },
    );
  }
}

class _FrostAlertCard extends StatelessWidget {
  const _FrostAlertCard({required this.child, this.headerActions});

  final Widget child;
  final List<Widget>? headerActions;

  @override
  Widget build(BuildContext context) {
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
                const Expanded(
                  child: Text(
                    'Frost Alert Status',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                ...?headerActions,
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Live status from the six-level frost alert engine for a selected zone.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _FrostStatusDisplay extends StatelessWidget {
  const _FrostStatusDisplay({required this.state});

  final FrostEngineState state;

  String _formatTemp(double? value) => value == null ? '—' : '${value.toStringAsFixed(1)}°F';
  String _formatRate(double? value) => value == null ? '—' : '${value.toStringAsFixed(1)}°F/hr';
  String _formatMph(double? value) => value == null ? '—' : '${value.toStringAsFixed(1)} mph';
  String _formatMinutes(double value) => '${value.round()} min';

  String _surfaceStatus() {
    final wet = state.leafWetness.isWet;
    final airTemp = state.derivedSnapshot.airTempF;

    // "Surface icing possible" when leaf wetness is active and canopy
    // temperature is approaching 32°F, per the spec's literal wording for
    // this display field (docs/Updated_Frost_Alert_Rules.pdf p.2/p.11) —
    // deliberately the fixed 32°F, not the farmer-configurable critical
    // threshold the rule engine itself uses for Imminent/Event.
    final icingPossible = wet && airTemp != null && airTemp <= 34;

    final parts = <String>[wet ? 'Wet' : 'Dry'];
    if (icingPossible) parts.add('surface icing possible');

    var result = parts.join('; ');
    final subtype = state.activeSubWarning;
    if (subtype != null) {
      result += ' (Type: ${_kSubWarningLabel[subtype] ?? subtype})';
    }
    return result;
  }

  /// A local, illustrative preview of what a transition notification would
  /// say — mirrors the wording style of the spec's example notifications.
  /// Not the source of truth for actual dispatched notifications; that's
  /// `functions/lib/frostEngine/messages.js` (plan §2, not yet built).
  String _messagePreview() {
    final snap = state.derivedSnapshot;
    final tempStr = _formatTemp(snap.airTempF);

    switch (state.currentLevel) {
      case 'normal':
        return 'No frost concern currently.';
      case 'watch':
        final rate = snap.coolingRate60FPerHr;
        final rateStr = rate == null ? '' : ', declining ${rate.abs().toStringAsFixed(1)}°F/hour';
        return 'Vineyard temperature is falling. Current temperature $tempStr$rateStr. Continue monitoring.';
      case 'warning':
        if (state.activeSubWarning == 'advective') {
          final windStr = snap.windSpeedMph == null
              ? ''
              : ', sustained wind is ${snap.windSpeedMph!.toStringAsFixed(1)} mph';
          return 'A regional freeze is approaching. Bud-zone temperature is $tempStr and falling$windStr. '
              'Wind-based mixing may provide limited protection.';
        }
        return 'Bud-zone temperature is $tempStr and falling. Conditions favor surface frost. '
            'Prepare the approved frost-protection procedure.';
      case 'imminent':
        return 'Measured bud-zone temperature has reached $tempStr. Initiate the vineyard\'s '
            'frost-protection procedure immediately.';
      case 'event':
        final minutes = state.eventAccumulators.timeBelowCriticalMinutes.round();
        return 'Bud-zone temperature has remained below the configured critical threshold for '
            '$minutes min. Continue the vineyard\'s approved frost-protection procedure and monitoring.';
      case 'allClear':
        return 'The current frost event has ended. Bud-zone temperature has recovered and remained '
            'stable or rising. Continue routine monitoring.';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = _kLevelMeta[state.currentLevel] ?? const _LevelMeta('Unknown', AppColors.textMuted);
    final snap = state.derivedSnapshot;
    final sensorUnavailable = state.dataQuality.overallFlag == 'sensor_unavailable';
    final showEventDetails = state.currentLevel == 'imminent' ||
        state.currentLevel == 'event' ||
        state.currentLevel == 'allClear';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: meta.color.withAlpha((0.15 * 255).toInt()),
                border: Border.all(color: meta.color),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                meta.label,
                style: TextStyle(color: meta.color, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        if (sensorUnavailable) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              border: Border.all(color: AppColors.errorBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Sensor data unavailable — showing the last known alert level.',
              style: TextStyle(color: AppColors.errorDark),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(_messagePreview(), style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),
        _statRow('Air temperature', _formatTemp(snap.airTempF)),
        _statRow('Dew point', _formatTemp(snap.dewPointF)),
        _statRow('Dew-point spread', _formatTemp(snap.dewPointSpreadF)),
        _statRow('Leaf condition', state.leafWetness.isWet ? 'Wet' : 'Dry'),
        _statRow('Continuous wetness', _formatMinutes(state.leafWetness.continuousWetnessMinutes)),
        _statRow('Wind speed', _formatMph(snap.windSpeedMph)),
        _statRow('Surface status', _surfaceStatus()),
        if (showEventDetails) ...[
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 4),
          Text('Event details', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _statRow('Time below critical threshold', _formatMinutes(state.eventAccumulators.timeBelowCriticalMinutes)),
          _statRow('Time below 32°F', _formatMinutes(state.eventAccumulators.timeBelow32Minutes)),
          _statRow('Time below 30°F', _formatMinutes(state.eventAccumulators.timeBelow30Minutes)),
          _statRow('Minimum temperature', _formatTemp(state.eventAccumulators.minTempF)),
          _statRow('Maximum cooling rate', _formatRate(state.eventAccumulators.maxCoolingRateFPerHr)),
          _statRow('Wind classification', snap.windClassLabel ?? '—'),
        ],
      ],
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: AppColors.textMuted)),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
