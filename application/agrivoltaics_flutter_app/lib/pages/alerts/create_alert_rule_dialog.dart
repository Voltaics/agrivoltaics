import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../app_colors.dart';
import '../../models/alert_rule.dart';
import '../../services/alert_service.dart';
import '../../services/readings_service.dart';

class CreateAlertRuleDialog extends StatefulWidget {
  final String orgId;
  final AlertRule? existingRule;

  const CreateAlertRuleDialog({
    super.key,
    required this.orgId,
    this.existingRule,
  });

  @override
  State<CreateAlertRuleDialog> createState() => _CreateAlertRuleDialogState();
}

class _CreateAlertRuleDialogState extends State<CreateAlertRuleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _alertService = AlertService();
  final _readingsService = ReadingsService();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _thresholdCtrl;
  late final TextEditingController _dateStartCtrl;
  late final TextEditingController _dateEndCtrl;
  late final TextEditingController _cooldownCtrl;

  // Frost-specific controllers
  late final TextEditingController _tempDropRateCtrl;
  late final TextEditingController _humidityMinCtrl;
  late final TextEditingController _airTempMaxCtrl;
  late final TextEditingController _soilTempMaxCtrl;
  late final TextEditingController _lightMaxCtrl;
  late bool _requireLowLight;

  // mold specific controllers
  late final TextEditingController _moldHumidityMinCtrl;
  late final TextEditingController _moldTempMinCtrl;
  late final TextEditingController _moldTempMaxCtrl;
  late final TextEditingController _moldLightMaxCtrl;
  late final TextEditingController _moldSoilMoistureMinCtrl;
  late final TextEditingController _moldDurationHoursCtrl;

  // black rot specific controllers
  late final TextEditingController _blackRotHumidityMinCtrl;
  late final TextEditingController _blackRotTempMinCtrl;
  late final TextEditingController _blackRotTempMaxCtrl;
  late final TextEditingController _blackRotSoilMoistureJumpCtrl;
  late final TextEditingController _blackRotFollowupHoursCtrl;

  late AlertRuleType _ruleType;
  late AlertOperator _operator;
  late String? _fieldAlias;
  late bool _enabled;
  late bool _useTimeWindow;

  List<Map<String, dynamic>> _members = [];
  final Set<String> _selectedUserIds = {};
  bool _loadingMembers = true;
  bool _saving = false;

  bool get _isEdit => widget.existingRule != null;
  bool get _isThresholdRule => _ruleType == AlertRuleType.threshold;
  bool get _isFrostRule => _ruleType == AlertRuleType.frostWarning;
  bool get _isMoldRule => _ruleType == AlertRuleType.moldRisk;
  bool get _isBlackRotRule => _ruleType == AlertRuleType.blackRotRisk;

  @override
  void initState() {
    super.initState();
    final rule = widget.existingRule;

    _nameCtrl = TextEditingController(text: rule?.name ?? '');
    _thresholdCtrl = TextEditingController(
      text: rule?.threshold?.toString() ?? '',
    );
    _dateStartCtrl = TextEditingController(text: rule?.activeRangeStart ?? '');
    _dateEndCtrl = TextEditingController(text: rule?.activeRangeEnd ?? '');
    _cooldownCtrl = TextEditingController(
      text: rule?.cooldownMinutes.toString() ?? '60',
    );

    final config = rule?.ruleConfig;

    final frost = rule?.ruleType == AlertRuleType.frostWarning ? config : null;
    _tempDropRateCtrl = TextEditingController(
      text: (frost?['tempDropRateFPerHour'] ?? 2.0).toString(),
    );
    _humidityMinCtrl = TextEditingController(
      text: (frost?['humidityMin'] ?? 90.0).toString(),
    );
    _airTempMaxCtrl = TextEditingController(
      text: (frost?['airTempMaxF'] ?? 39.0).toString(),
    );
    _soilTempMaxCtrl = TextEditingController(
      text: (frost?['soilTempMaxF'] ?? 45.0).toString(),
    );
    _lightMaxCtrl = TextEditingController(
      text: (frost?['lightMax'] ?? 5.0).toString(),
    );
    _requireLowLight = (frost?['requireLowLight'] ?? true) == true;

    final mold = rule?.ruleType == AlertRuleType.moldRisk ? config : null;
    _moldHumidityMinCtrl = TextEditingController(
      text: (mold?['humidityMin'] ?? 85.0).toString(),
    );
    _moldTempMinCtrl = TextEditingController(
      text: (mold?['tempMinF'] ?? 68.0).toString(),
    );
    _moldTempMaxCtrl = TextEditingController(
      text: (mold?['tempMaxF'] ?? 86.0).toString(),
    );
    _moldLightMaxCtrl = TextEditingController(
      text: (mold?['lightMax'] ?? 5.0).toString(),
    );
    _moldSoilMoistureMinCtrl = TextEditingController(
      text: (mold?['soilMoistureMin'] ?? 40.0).toString(),
    );
    _moldDurationHoursCtrl = TextEditingController(
      text: (mold?['durationHours'] ?? 6.0).toString(),
    );

    final blackRot = rule?.ruleType == AlertRuleType.blackRotRisk ? config : null;
    _blackRotHumidityMinCtrl = TextEditingController(
      text: (blackRot?['humidityMin'] ?? 90.0).toString(),
    );
    _blackRotTempMinCtrl = TextEditingController(
      text: (blackRot?['tempMinF'] ?? 70.0).toString(),
    );
    _blackRotTempMaxCtrl = TextEditingController(
      text: (blackRot?['tempMaxF'] ?? 85.0).toString(),
    );
    _blackRotSoilMoistureJumpCtrl = TextEditingController(
      text: (blackRot?['soilMoistureJump'] ?? 8.0).toString(),
    );
    _blackRotFollowupHoursCtrl = TextEditingController(
      text: (blackRot?['followupHours'] ?? 48.0).toString(),
    );

    _ruleType = rule?.ruleType ?? AlertRuleType.threshold;
    _operator = rule?.operator ?? AlertOperator.gt;
    _fieldAlias = rule?.fieldAlias.isNotEmpty == true ? rule!.fieldAlias : null;
    _enabled = rule?.enabled ?? true;
    _useTimeWindow =
        rule?.activeRangeStart != null && rule?.activeRangeEnd != null;

    if (rule != null) {
      _selectedUserIds.addAll(rule.notifyUserIds);
    }

    // Good default season windows for new alert rules
    if (!_isEdit && _ruleType == AlertRuleType.frostWarning) {
      _dateStartCtrl.text = '04/01';
      _dateEndCtrl.text = '05/31';
    } else if (!_isEdit &&
        (_ruleType == AlertRuleType.moldRisk ||
            _ruleType == AlertRuleType.blackRotRisk)) {
      _dateStartCtrl.text = '06/01';
      _dateEndCtrl.text = '08/31';
    }

    _loadMembers();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _thresholdCtrl.dispose();
    _dateStartCtrl.dispose();
    _dateEndCtrl.dispose();
    _cooldownCtrl.dispose();

    _tempDropRateCtrl.dispose();
    _humidityMinCtrl.dispose();
    _airTempMaxCtrl.dispose();
    _soilTempMaxCtrl.dispose();
    _lightMaxCtrl.dispose();

    _moldHumidityMinCtrl.dispose();
    _moldTempMinCtrl.dispose();
    _moldTempMaxCtrl.dispose();
    _moldLightMaxCtrl.dispose();
    _moldSoilMoistureMinCtrl.dispose();
    _moldDurationHoursCtrl.dispose();

    _blackRotHumidityMinCtrl.dispose();
    _blackRotTempMinCtrl.dispose();
    _blackRotTempMaxCtrl.dispose();
    _blackRotSoilMoistureJumpCtrl.dispose();
    _blackRotFollowupHoursCtrl.dispose();

    super.dispose();
  }

  Future<void> _loadMembers() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('organizations/${widget.orgId}/members')
          .get();

      final members = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final userId = doc.id;
        final userDoc = await FirebaseFirestore.instance.doc('users/$userId').get();
        if (userDoc.exists) {
          final data = userDoc.data() as Map<String, dynamic>;
          members.add({
            'userId': userId,
            'email': data['email'] ?? '',
            'displayName': data['displayName'] ?? data['email'] ?? userId,
          });
        }
      }

      if (!mounted) return;
      setState(() {
        _members = members;
        _loadingMembers = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

    Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final String? timeStart =
          _useTimeWindow && _dateStartCtrl.text.isNotEmpty
              ? _dateStartCtrl.text.trim()
              : null;
      final String? timeEnd =
          _useTimeWindow && _dateEndCtrl.text.isNotEmpty
              ? _dateEndCtrl.text.trim()
              : null;
      final int cooldown = int.tryParse(_cooldownCtrl.text.trim()) ?? 60;

      Map<String, dynamic> payload;

      if (_isThresholdRule) {
        final threshold = double.parse(_thresholdCtrl.text.trim());

        payload = {
          'name': _nameCtrl.text.trim(),
          'ruleType': AlertRuleType.threshold.value,
          'fieldAlias': _fieldAlias!,
          'operator': _operator.value,
          'threshold': threshold,
          'ruleConfig': null,
          'frostConfig': null,
          'enabled': _enabled,
          'notifyUserIds': _selectedUserIds.toList(),
          'activeRangeStart': timeStart,
          'activeRangeEnd': timeEnd,
          'cooldownMinutes': cooldown,
        };
      } else if (_isFrostRule) {
        payload = {
          'name': _nameCtrl.text.trim(),
          'ruleType': AlertRuleType.frostWarning.value,
          'fieldAlias': '',
          'operator': null,
          'threshold': null,
          'ruleConfig': {
            'tempDropRateFPerHour': double.parse(_tempDropRateCtrl.text.trim()),
            'humidityMin': double.parse(_humidityMinCtrl.text.trim()),
            'airTempMaxF': double.parse(_airTempMaxCtrl.text.trim()),
            'soilTempMaxF': double.parse(_soilTempMaxCtrl.text.trim()),
            'lightMax': double.parse(_lightMaxCtrl.text.trim()),
            'requireLowLight': _requireLowLight,
          },
          // keep for backward compatibility if other code still reads frostConfig
          'frostConfig': {
            'tempDropRateFPerHour': double.parse(_tempDropRateCtrl.text.trim()),
            'humidityMin': double.parse(_humidityMinCtrl.text.trim()),
            'airTempMaxF': double.parse(_airTempMaxCtrl.text.trim()),
            'soilTempMaxF': double.parse(_soilTempMaxCtrl.text.trim()),
            'lightMax': double.parse(_lightMaxCtrl.text.trim()),
            'requireLowLight': _requireLowLight,
          },
          'enabled': _enabled,
          'notifyUserIds': _selectedUserIds.toList(),
          'activeRangeStart': timeStart,
          'activeRangeEnd': timeEnd,
          'cooldownMinutes': cooldown,
        };
      } else if (_isMoldRule) {
        payload = {
          'name': _nameCtrl.text.trim(),
          'ruleType': AlertRuleType.moldRisk.value,
          'fieldAlias': '',
          'operator': null,
          'threshold': null,
          'ruleConfig': {
            'humidityMin': double.parse(_moldHumidityMinCtrl.text.trim()),
            'tempMinF': double.parse(_moldTempMinCtrl.text.trim()),
            'tempMaxF': double.parse(_moldTempMaxCtrl.text.trim()),
            'lightMax': double.parse(_moldLightMaxCtrl.text.trim()),
            'soilMoistureMin': double.parse(_moldSoilMoistureMinCtrl.text.trim()),
            'durationHours': double.parse(_moldDurationHoursCtrl.text.trim()),
          },
          'frostConfig': null,
          'enabled': _enabled,
          'notifyUserIds': _selectedUserIds.toList(),
          'activeRangeStart': timeStart,
          'activeRangeEnd': timeEnd,
          'cooldownMinutes': cooldown,
        };
      } else if (_isBlackRotRule) {
        payload = {
          'name': _nameCtrl.text.trim(),
          'ruleType': AlertRuleType.blackRotRisk.value,
          'fieldAlias': '',
          'operator': null,
          'threshold': null,
          'ruleConfig': {
            'humidityMin': double.parse(_blackRotHumidityMinCtrl.text.trim()),
            'tempMinF': double.parse(_blackRotTempMinCtrl.text.trim()),
            'tempMaxF': double.parse(_blackRotTempMaxCtrl.text.trim()),
            'soilMoistureJump': double.parse(_blackRotSoilMoistureJumpCtrl.text.trim()),
            'followupHours': double.parse(_blackRotFollowupHoursCtrl.text.trim()),
          },
          'frostConfig': null,
          'enabled': _enabled,
          'notifyUserIds': _selectedUserIds.toList(),
          'activeRangeStart': timeStart,
          'activeRangeEnd': timeEnd,
          'cooldownMinutes': cooldown,
        };
      } else {
        throw Exception('Unsupported alert rule type.');
      }

      if (_isEdit) {
        await _alertService.updateAlertRule(
          widget.orgId,
          widget.existingRule!.id,
          payload,
        );
      } else {
        await _alertService.createAlertRule(
          orgId: widget.orgId,
          payload: payload,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving alert rule: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final readings = _readingsService.getAllReadings();
    final fieldOptions = readings.entries.toList();
    final media = MediaQuery.of(context);
    final isDesktop = media.size.width >= 1280;
    final maxDialogWidth = media.size.width * 0.95;
    final preferredWidth = isDesktop ? 700.0 : 560.0;
    final dialogWidth =
        maxDialogWidth > preferredWidth ? preferredWidth : maxDialogWidth;
    final maxDialogHeight = media.size.height * (isDesktop ? 0.88 : 0.94);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: dialogWidth,
        height: maxDialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: [
                  const Icon(Icons.notifications_active, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isEdit ? 'Edit Alert Rule' : 'New Alert Rule',
                      style: Theme.of(context).textTheme.titleLarge,
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
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Rule Name',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.label_outline),
                          ),
                          validator: (v) =>
                              v == null || v.trim().isEmpty ? 'Name is required' : null,
                          enabled: !_saving,
                        ),
                        const SizedBox(height: 16),

                        DropdownButtonFormField<AlertRuleType>(
                          initialValue: _ruleType,
                          decoration: const InputDecoration(
                            labelText: 'Alert Type',
                            border: OutlineInputBorder(),
                          ),
                          items: AlertRuleType.values
                              .map(
                                (type) => DropdownMenuItem(
                                  value: type,
                                  child: Text(type.label),
                                ),
                              )
                              .toList(),
                          onChanged: _saving
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _ruleType = value;

                                    if (_nameCtrl.text.trim().isEmpty) {
                                      if (_ruleType == AlertRuleType.frostWarning) {
                                        _nameCtrl.text = 'Frost Warning';
                                      } else if (_ruleType == AlertRuleType.moldRisk) {
                                        _nameCtrl.text = 'Mold Risk';
                                      } else if (_ruleType == AlertRuleType.blackRotRisk) {
                                        _nameCtrl.text = 'Black Rot Risk';
                                      }
                                    }

                                    if (_ruleType == AlertRuleType.frostWarning) {
                                      _useTimeWindow = true;
                                      _dateStartCtrl.text = '04/01';
                                      _dateEndCtrl.text = '05/31';
                                    } else if (_ruleType == AlertRuleType.moldRisk ||
                                        _ruleType == AlertRuleType.blackRotRisk) {
                                      _useTimeWindow = true;
                                      _dateStartCtrl.text = '06/01';
                                      _dateEndCtrl.text = '08/31';
                                    }
                                  });
                                },
                        ),
                        const SizedBox(height: 16),

                        if (_isThresholdRule) ...[
                          const Text(
                            'Condition',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textOnLight,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: DropdownButtonFormField<String>(
                                  initialValue: _fieldAlias,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Field',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: fieldOptions
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e.key,
                                          child: Text(e.value.name),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: _saving
                                      ? null
                                      : (v) => setState(() => _fieldAlias = v),
                                  validator: (v) =>
                                      v == null ? 'Select a field' : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<AlertOperator>(
                                  initialValue: _operator,
                                  decoration: const InputDecoration(
                                    labelText: 'Operator',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: AlertOperator.values
                                      .map(
                                        (op) => DropdownMenuItem(
                                          value: op,
                                          child: Text(op.label),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: _saving
                                      ? null
                                      : (v) => setState(() => _operator = v!),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _thresholdCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Threshold',
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Required';
                                    }
                                    if (double.tryParse(v.trim()) == null) {
                                      return 'Invalid number';
                                    }
                                    return null;
                                  },
                                  enabled: !_saving,
                                ),
                              ),
                            ],
                          ),
                        ],

                        if (_isFrostRule) ...[
                          const Text(
                            'Frost Warning Rule',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textOnLight,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Triggers when evening cooling is fast, humidity is high, air temperature is in the 30s, soil is cold, and light is low.',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _tempDropRateCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Temperature drop rate threshold (°F/hour)',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: _validateDouble,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _humidityMinCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Minimum humidity (%)',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: _validateDouble,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _airTempMaxCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Maximum air temperature (°F)',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: _validateDouble,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _soilTempMaxCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Maximum soil temperature (°F)',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: _validateDouble,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _lightMaxCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Maximum light threshold',
                              border: OutlineInputBorder(),
                              helperText: 'Used as a proxy for darkness / likely clear-sky night',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: _validateDouble,
                          ),
                          SwitchListTile(
                            value: _requireLowLight,
                            onChanged: _saving
                                ? null
                                : (v) => setState(() => _requireLowLight = v),
                            title: const Text('Require low light / nighttime condition'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                        
                        if (_isMoldRule) ...[
                          const Text(
                            'Mold Risk Rule',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textOnLight,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Triggers when temperature is warm, humidity stays high for several hours, light is low, and soil moisture remains elevated.',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _moldHumidityMinCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Minimum humidity (%)',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: _validateDouble,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _moldTempMinCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Minimum air temperature (°F)',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: _validateDouble,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _moldTempMaxCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Maximum air temperature (°F)',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: _validateDouble,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _moldLightMaxCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Maximum light threshold',
                              border: OutlineInputBorder(),
                              helperText: 'Used as a proxy for low light / shade inside canopy',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: _validateDouble,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _moldSoilMoistureMinCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Minimum soil moisture',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: _validateDouble,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _moldDurationHoursCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Required duration (hours)',
                              border: OutlineInputBorder(),
                              helperText: 'How long conditions must persist before alerting',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: _validateDouble,
                          ),
                        ],

                        if (_isBlackRotRule) ...[
                          const Text(
                            'Black Rot Risk Rule',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textOnLight,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Triggers when soil moisture jumps, humidity is high, air temperature is warm, and those conditions continue during the follow-up window.',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _blackRotHumidityMinCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Minimum humidity (%)',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: _validateDouble,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _blackRotTempMinCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Minimum air temperature (°F)',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: _validateDouble,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _blackRotTempMaxCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Maximum air temperature (°F)',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: _validateDouble,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _blackRotSoilMoistureJumpCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Minimum soil moisture jump',
                              border: OutlineInputBorder(),
                              helperText: 'Increase required to count as a wetting / rain-like event',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: _validateDouble,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _blackRotFollowupHoursCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Follow-up window (hours)',
                              border: OutlineInputBorder(),
                              helperText: 'How long warm/humid conditions must continue after the wet event',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: _validateDouble,
                          ),
                        ],
                        
                        const SizedBox(height: 16),
                        SwitchListTile(
                          value: _useTimeWindow,
                          onChanged: _saving ? null : (v) => setState(() => _useTimeWindow = v),
                          title: const Text('Active only during season window'),
                          subtitle: const Text(
                            'Recommended for frost: 04/01\u201305/31',
                            style: TextStyle(fontSize: 12),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (_useTimeWindow) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _dateStartCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Start (MM/dd)',
                                    hintText: '04/01',
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: _useTimeWindow ? _validateDate : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: _dateEndCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'End (MM/dd)',
                                    hintText: '05/31',
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: _useTimeWindow ? _validateDate : null,
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _cooldownCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Cooldown (minutes)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.timer),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Required';
                            final n = int.tryParse(v.trim());
                            if (n == null || n < 0) return 'Must be a positive integer';
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),
                        const Text(
                          'Who to Notify',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textOnLight,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_loadingMembers)
                          const Center(child: CircularProgressIndicator())
                        else if (_members.isEmpty)
                          const Text('No members found in this organization.')
                        else
                          ..._members.map(
                            (m) => CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(m['displayName'] as String),
                              subtitle: Text(m['email'] as String),
                              value: _selectedUserIds.contains(m['userId']),
                              onChanged: _saving
                                  ? null
                                  : (checked) {
                                      setState(() {
                                        if (checked == true) {
                                          _selectedUserIds.add(m['userId'] as String);
                                        } else {
                                          _selectedUserIds.remove(m['userId'] as String);
                                        }
                                      });
                                    },
                            ),
                          ),

                        const SizedBox(height: 8),
                        SwitchListTile(
                          value: _enabled,
                          onChanged: _saving ? null : (v) => setState(() => _enabled = v),
                          title: const Text('Enabled'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
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
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'Saving...' : (_isEdit ? 'Save' : 'Create')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _validateDate(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final parts = value.trim().split('/');
    if (parts.length != 2) return 'Use MM/dd format';
    final month = int.tryParse(parts[0]);
    final day = int.tryParse(parts[1]);
    if (month == null || day == null || month < 1 || month > 12 || day < 1 || day > 31) {
      return 'Invalid date';
    }
    return null;
  }

  String? _validateDouble(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    if (double.tryParse(value.trim()) == null) return 'Invalid number';
    return null;
  }
}