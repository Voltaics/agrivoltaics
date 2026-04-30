import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_colors.dart';
import '../../../models/site.dart' as models;
import '../../../models/zone.dart';
import '../../../services/frost_settings_service.dart';
import '../../../services/site_service.dart';
import '../../../services/zone_service.dart';


class FrostSettingsDialog extends StatefulWidget {
  const FrostSettingsDialog({
    super.key,
    required this.orgId,
    this.initialSiteId,
    this.initialZoneId,
  });

  final String orgId;
  final String? initialSiteId;
  final String? initialZoneId;

  @override
  State<FrostSettingsDialog> createState() => _FrostSettingsDialogState();
}

class _FrostSettingsDialogState extends State<FrostSettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _siteService = SiteService();
  final _zoneService = ZoneService();
  final _frostSettingsService = const FrostSettingsService();
  final _dateFormat = DateFormat('MMM d, yyyy h:mm a');

  late final Stream<List<models.Site>> _sitesStream;
  Stream<List<Zone>>? _zonesStream;
  String? _zonesStreamSiteId;

  late final TextEditingController _predStartCtrl;
  late final TextEditingController _predEndCtrl;
  late final TextEditingController _tempThresholdCtrl;

  final GlobalKey _settingsFieldsKey = GlobalKey();
  late final FocusNode _tempThresholdFocusNode;
  late final ScrollController _scrollController;

  final Map<String, _FrostSettingsDraft> _draftsByZoneKey = {};
  final Set<String> _dirtyZoneKeys = {};
  final Set<String> _loadedZoneKeys = {};

  String? _selectedSiteId;
  String? _selectedZoneId;

  DateTime? _predStart;
  DateTime? _predEnd;
  bool _enabled = true;

  bool _loadingSettings = false;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();

    _sitesStream = _siteService.getSites(widget.orgId);

    _selectedSiteId = widget.initialSiteId;
    _selectedZoneId = widget.initialZoneId;

    _predStartCtrl = TextEditingController();
    _predEndCtrl = TextEditingController();
    _tempThresholdCtrl = TextEditingController();

    _scrollController = ScrollController();

    _tempThresholdFocusNode = FocusNode();
    _tempThresholdFocusNode.addListener(_handleTempThresholdFocusChange);

    if (_selectedSiteId != null && _selectedZoneId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadOrApplySettingsForSelectedZone();
      });
    }
  }

  @override
  void dispose() {
    _tempThresholdFocusNode.removeListener(_handleTempThresholdFocusChange);
    _tempThresholdFocusNode.dispose();
    _scrollController.dispose();

    _predStartCtrl.dispose();
    _predEndCtrl.dispose();
    _tempThresholdCtrl.dispose();
    super.dispose();
  }

  void _ensureZonesStreamForSite(String siteId) {
    if (_zonesStreamSiteId == siteId && _zonesStream != null) return;

    _zonesStreamSiteId = siteId;
    _zonesStream = _zoneService.getZones(widget.orgId, siteId);
  }

  void _handleTempThresholdFocusChange() {
    if (!_tempThresholdFocusNode.hasFocus) return;

    Future.delayed(const Duration(milliseconds: 450), () {
      if (!mounted || !_tempThresholdFocusNode.hasFocus) return;
      _scrollTempThresholdIntoView();
    });
  }

  void _scrollTempThresholdIntoView() {
    if (!_scrollController.hasClients) return;

    final maxScrollExtent = _scrollController.position.maxScrollExtent;

    _scrollController.animateTo(
      maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  String _zoneKey(String siteId, String zoneId) => '$siteId::$zoneId';

  String? get _selectedZoneKey {
    final siteId = _selectedSiteId;
    final zoneId = _selectedZoneId;

    if (siteId == null || zoneId == null) return null;

    return _zoneKey(siteId, zoneId);
  }

  void _rememberCurrentEdits({bool markDirty = true}) {
    final siteId = _selectedSiteId;
    final zoneId = _selectedZoneId;

    if (siteId == null || zoneId == null) return;

    final key = _zoneKey(siteId, zoneId);

    _draftsByZoneKey[key] = _FrostSettingsDraft(
      siteId: siteId,
      zoneId: zoneId,
      enabled: _enabled,
      predStart: _predStart,
      predEnd: _predEnd,
      tempThresholdText: _tempThresholdCtrl.text.trim(),
    );

    if (markDirty && _loadedZoneKeys.contains(key)) {
      _dirtyZoneKeys.add(key);
    }
  }

  void _applyDraftToFields(_FrostSettingsDraft draft) {
    _enabled = draft.enabled;
    _predStart = draft.predStart;
    _predEnd = draft.predEnd;
    _tempThresholdCtrl.text = draft.tempThresholdText;
    _syncDateControllers();
  }

  Future<void> _loadOrApplySettingsForSelectedZone() async {
    final siteId = _selectedSiteId;
    final zoneId = _selectedZoneId;

    if (siteId == null || zoneId == null) return;

    final key = _zoneKey(siteId, zoneId);
    final cachedDraft = _draftsByZoneKey[key];

    if (cachedDraft != null) {
      setState(() {
        _loadError = null;
        _applyDraftToFields(cachedDraft);
      });
      return;
    }

    setState(() {
      _loadingSettings = true;
      _loadError = null;
    });

    try {
      final settings = await _frostSettingsService.getFrostSettings(
        orgId: widget.orgId,
        siteId: siteId,
        zoneId: zoneId,
      );

      if (!mounted) return;

      final draft = _FrostSettingsDraft.fromSettings(
        siteId: siteId,
        zoneId: zoneId,
        settings: settings,
      );

      setState(() {
        _draftsByZoneKey[key] = draft;
        _loadedZoneKeys.add(key);
        _applyDraftToFields(draft);
        _loadingSettings = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingSettings = false;
        _loadError = 'Error loading frost settings: $e';
      });
    }
  }

  Future<void> _save() async {
    _rememberCurrentEdits();

    if (!_formKey.currentState!.validate()) return;

    final invalidDraftMessage = _validateAllDirtyDrafts();
    if (invalidDraftMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(invalidDraftMessage),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_dirtyZoneKeys.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }

    setState(() => _saving = true);

    try {
      for (final key in _dirtyZoneKeys) {
        final draft = _draftsByZoneKey[key];

        if (draft == null) continue;

        await _frostSettingsService.saveFrostSettings(
          orgId: widget.orgId,
          siteId: draft.siteId,
          zoneId: draft.zoneId,
          settings: draft.toSettings(),
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving frost settings: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  String? _validateAllDirtyDrafts() {
    for (final key in _dirtyZoneKeys) {
      final draft = _draftsByZoneKey[key];

      if (draft == null) continue;

      final threshold = int.tryParse(draft.tempThresholdText);

      if (draft.predStart == null) {
        return 'One changed zone is missing a prediction start.';
      }

      if (draft.predEnd == null) {
        return 'One changed zone is missing a prediction end.';
      }

      if (!draft.predEnd!.isAfter(draft.predStart!)) {
        return 'One changed zone has a prediction end before its prediction start.';
      }

      if (threshold == null) {
        return 'One changed zone has an invalid temperature threshold.';
      }

      if (threshold < -100 || threshold > 150) {
        return 'One changed zone has an unrealistic temperature threshold.';
      }
    }

    return null;
  }

  Future<void> _pickDateTime({
    required bool isStart,
  }) async {
    final currentValue = isStart ? _predStart : _predEnd;
    final initialDate = currentValue ?? DateTime.now();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );

    if (pickedTime == null || !mounted) return;

    final pickedDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    setState(() {
      if (isStart) {
        _predStart = pickedDateTime;
      } else {
        _predEnd = pickedDateTime;
      }

      _syncDateControllers();
      _rememberCurrentEdits();
    });
  }

  void _syncDateControllers() {
    _predStartCtrl.text = _predStart == null ? '' : _dateFormat.format(_predStart!);
    _predEndCtrl.text = _predEnd == null ? '' : _dateFormat.format(_predEnd!);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isDesktop = media.size.width >= 1280;
    final maxDialogWidth = media.size.width * 0.95;
    final preferredWidth = isDesktop ? 700.0 : 560.0;
    final dialogWidth =
        maxDialogWidth > preferredWidth ? preferredWidth : maxDialogWidth;
    final verticalInset = isDesktop ? 24.0 : 12.0;

    final maxDialogHeight = media.size.height * (isDesktop ? 0.9 : 0.86);

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: verticalInset,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: maxDialogHeight,
        ),
        child: SizedBox(
          width: dialogWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Row(
                  children: [
                    const Icon(Icons.settings, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Frost Prediction Settings',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (_dirtyZoneKeys.isNotEmpty)
                      Text(
                        '${_dirtyZoneKeys.length} unsaved',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Form(
                    key: _formKey,
                    child: StreamBuilder<List<models.Site>>(
                      stream: _sitesStream,
                      builder: (context, siteSnapshot) {
                        Widget body;

                        if (siteSnapshot.connectionState == ConnectionState.waiting) {
                          body = const Center(child: CircularProgressIndicator());
                        } else if (siteSnapshot.hasError) {
                          body = Text('Error loading sites: ${siteSnapshot.error}');
                        } else {
                          final sites = siteSnapshot.data ?? [];

                          if (sites.isEmpty) {
                            body = const Text('No sites found for this organization.');
                          } else {
                            final selectedSiteStillExists =
                                sites.any((site) => site.id == _selectedSiteId);

                            if (!selectedSiteStillExists && _selectedSiteId != null) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                setState(() {
                                  _rememberCurrentEdits();
                                  _selectedSiteId = null;
                                  _selectedZoneId = null;
                                });
                              });
                            }

                            body = Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Select a site and zone, make changes, then move to another zone if needed. '
                                  'All changed zones are saved together when you press Save.',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                DropdownButtonFormField<String>(
                                  initialValue: selectedSiteStillExists ? _selectedSiteId : null,
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
                                  onChanged: _saving
                                      ? null
                                      : (siteId) {
                                          setState(() {
                                            _rememberCurrentEdits();
                                            _selectedSiteId = siteId;
                                            _selectedZoneId = null;
                                            _loadError = null;

                                            if (siteId != null) {
                                              _ensureZonesStreamForSite(siteId);
                                            } else {
                                              _zonesStream = null;
                                              _zonesStreamSiteId = null;
                                            }
                                          });
                                        },
                                  validator: (value) => value == null ? 'Select a site' : null,
                                ),
                                const SizedBox(height: 12),
                                if (_selectedSiteId == null)
                                  const Text('Choose a site to load zones.')
                                else
                                  _buildZoneSelector(),
                                const SizedBox(height: 16),
                                if (_loadingSettings)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                        SizedBox(width: 10),
                                        Text('Loading frost settings...'),
                                      ],
                                    ),
                                  ),
                                if (_loadError != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Text(
                                      _loadError!,
                                      style: const TextStyle(color: AppColors.error),
                                    ),
                                  ),
                                if (_selectedSiteId != null && _selectedZoneId != null)
                                  KeyedSubtree(
                                    key: _settingsFieldsKey,
                                    child: _buildSettingsFields(),
                                  ),
                              ],
                            );
                          }
                        }

                        return SingleChildScrollView(
                          controller: _scrollController,
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                          padding: const EdgeInsets.only(bottom: 260),
                          child: body,
                        );
                      },
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 16, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _saving || _loadingSettings ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: Text(_saving ? 'Saving...' : 'Save'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildZoneSelector() {
    final siteId = _selectedSiteId;

    if (siteId == null) {
      return const Text('Choose a site to load zones.');
    }

    _ensureZonesStreamForSite(siteId);

    final zonesStream = _zonesStream;

    if (zonesStream == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return StreamBuilder<List<Zone>>(
      stream: zonesStream,
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
            .where((zone) => zone.zoneChecked)
            .toList();

        if (zones.isEmpty) {
          return const Text('No enabled zones available for this site.');
        }

        final selectedZoneStillExists =
            zones.any((zone) => zone.id == _selectedZoneId);

        if (!selectedZoneStillExists && _selectedZoneId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _rememberCurrentEdits();
              _selectedZoneId = null;
            });
          });
        }

        return DropdownButtonFormField<String>(
          initialValue: selectedZoneStillExists ? _selectedZoneId : null,
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
          onChanged: _saving
              ? null
              : (zoneId) {
                  setState(() {
                    _rememberCurrentEdits();
                    _selectedZoneId = zoneId;
                    _loadError = null;
                  });
                  _loadOrApplySettingsForSelectedZone();
                },
          validator: (value) => value == null ? 'Select a zone' : null,
        );
      },
    );
  }

  Widget _buildSettingsFields() {
    final selectedKey = _selectedZoneKey;
    final hasUnsavedChanges =
        selectedKey != null && _dirtyZoneKeys.contains(selectedKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Frost Settings',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textOnLight,
                ),
              ),
            ),
            if (hasUnsavedChanges)
              const Text(
                'Unsaved changes',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'These values are stored on the selected zone under the frostSettings map.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          value: _enabled,
          onChanged: _saving
              ? null
              : (value) {
                  setState(() {
                    _enabled = value;
                    _rememberCurrentEdits();
                  });
                },
          title: const Text('Enabled'),
          subtitle: const Text('Controls whether frost prediction is enabled for this zone.'),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _predStartCtrl,
          readOnly: true,
          autofillHints: const [],
          scrollPadding: const EdgeInsets.only(bottom: 140),
          decoration: const InputDecoration(
            labelText: 'Prediction start',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.event_available),
            suffixIcon: Icon(Icons.edit_calendar),
          ),
          onTap: _saving ? null : () => _pickDateTime(isStart: true),
          validator: (_) => _predStart == null ? 'Prediction start is required' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _predEndCtrl,
          readOnly: true,
          autofillHints: const [],
          scrollPadding: const EdgeInsets.only(bottom: 140),
          decoration: const InputDecoration(
            labelText: 'Prediction end',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.event_busy),
            suffixIcon: Icon(Icons.edit_calendar),
          ),
          onTap: _saving ? null : () => _pickDateTime(isStart: false),
          validator: (_) {
            if (_predEnd == null) return 'Prediction end is required';
            if (_predStart != null && !_predEnd!.isAfter(_predStart!)) {
              return 'Prediction end must be after prediction start';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _tempThresholdCtrl,
          focusNode: _tempThresholdFocusNode,
          autofillHints: const [],
          scrollPadding: const EdgeInsets.only(bottom: 180),
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Temperature threshold (°F)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.thermostat),
            helperText: 'Maximum temperature at which frost prediction is triggered',
          ),
          keyboardType: TextInputType.number,
          validator: _validateInt,
          enabled: !_saving,
          onChanged: (_) => _rememberCurrentEdits(),
        ),
      ],
    );
  }

  String? _validateInt(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';

    final parsed = int.tryParse(value.trim());
    if (parsed == null) return 'Invalid whole number';

    if (parsed < -100 || parsed > 150) {
      return 'Enter a realistic Fahrenheit temperature';
    }

    return null;
  }
}

class _FrostSettingsDraft {
  const _FrostSettingsDraft({
    required this.siteId,
    required this.zoneId,
    required this.enabled,
    required this.predStart,
    required this.predEnd,
    required this.tempThresholdText,
  });

  final String siteId;
  final String zoneId;
  final bool enabled;
  final DateTime? predStart;
  final DateTime? predEnd;
  final String tempThresholdText;

  factory _FrostSettingsDraft.fromSettings({
    required String siteId,
    required String zoneId,
    required FrostSettings settings,
  }) {
    return _FrostSettingsDraft(
      siteId: siteId,
      zoneId: zoneId,
      enabled: settings.enabled,
      predStart: settings.predStart,
      predEnd: settings.predEnd,
      tempThresholdText: settings.tempThresholdF.toString(),
    );
  }

  FrostSettings toSettings() {
    return FrostSettings(
      enabled: enabled,
      predStart: predStart!,
      predEnd: predEnd!,
      tempThresholdF: int.parse(tempThresholdText),
    );
  }
}