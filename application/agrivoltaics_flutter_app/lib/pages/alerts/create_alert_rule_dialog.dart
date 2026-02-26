import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app_colors.dart';
import '../../models/alert_rule.dart';
import '../../services/alert_service.dart';
import '../../services/readings_service.dart';
import '../../services/user_service.dart';

/// Dialog for creating a new [AlertRule] or editing an existing one.
class CreateAlertRuleDialog extends StatefulWidget {
  final String orgId;

  /// When non-null the dialog is in "edit" mode.
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
  final _userService = UserService();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _thresholdCtrl;
  late final TextEditingController _timeStartCtrl;
  late final TextEditingController _timeEndCtrl;

  late AlertOperator _operator;
  late String? _fieldAlias;
  late bool _enabled;
  late bool _useTimeWindow;

  // Members fetched from Firestore for the "who to notify" selector.
  List<Map<String, dynamic>> _members = [];
  final Set<String> _selectedUserIds = {};
  bool _loadingMembers = true;
  bool _saving = false;

  bool get _isEdit => widget.existingRule != null;

  @override
  void initState() {
    super.initState();
    final rule = widget.existingRule;
    _nameCtrl = TextEditingController(text: rule?.name ?? '');
    _thresholdCtrl =
        TextEditingController(text: rule?.threshold.toString() ?? '');
    _timeStartCtrl = TextEditingController(text: rule?.activeTimeStart ?? '');
    _timeEndCtrl = TextEditingController(text: rule?.activeTimeEnd ?? '');
    _operator = rule?.operator ?? AlertOperator.gt;
    _fieldAlias = rule?.fieldAlias.isNotEmpty == true ? rule!.fieldAlias : null;
    _enabled = rule?.enabled ?? true;
    _useTimeWindow =
        rule?.activeTimeStart != null && rule?.activeTimeEnd != null;
    if (rule != null) _selectedUserIds.addAll(rule.notifyUserIds);
    _loadMembers();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _thresholdCtrl.dispose();
    _timeStartCtrl.dispose();
    _timeEndCtrl.dispose();
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
        final userDoc = await FirebaseFirestore.instance
            .doc('users/$userId')
            .get();
        if (userDoc.exists) {
          final data = userDoc.data() as Map<String, dynamic>;
          members.add({
            'userId': userId,
            'email': data['email'] ?? '',
            'displayName': data['displayName'] ?? data['email'] ?? userId,
          });
        }
      }

      if (mounted) {
        setState(() {
          _members = members;
          _loadingMembers = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final String? timeStart =
          _useTimeWindow && _timeStartCtrl.text.isNotEmpty
              ? _timeStartCtrl.text.trim()
              : null;
      final String? timeEnd =
          _useTimeWindow && _timeEndCtrl.text.isNotEmpty
              ? _timeEndCtrl.text.trim()
              : null;
      final threshold = double.parse(_thresholdCtrl.text.trim());

      if (_isEdit) {
        await _alertService.updateAlertRule(
          widget.orgId,
          widget.existingRule!.id,
          {
            'name': _nameCtrl.text.trim(),
            'fieldAlias': _fieldAlias!,
            'operator': _operator.value,
            'threshold': threshold,
            'enabled': _enabled,
            'notifyUserIds': _selectedUserIds.toList(),
            'activeTimeStart': timeStart,
            'activeTimeEnd': timeEnd,
          },
        );
      } else {
        await _alertService.createAlertRule(
          orgId: widget.orgId,
          name: _nameCtrl.text.trim(),
          fieldAlias: _fieldAlias!,
          operator: _operator,
          threshold: threshold,
          enabled: _enabled,
          notifyUserIds: _selectedUserIds.toList(),
          activeTimeStart: timeStart,
          activeTimeEnd: timeEnd,
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

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.notifications_active, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(_isEdit ? 'Edit Alert Rule' : 'New Alert Rule'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Name ─────────────────────────────────────────────────────
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Rule Name',
                    hintText: 'e.g., Low Temperature Alert',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.label_outline),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Name is required' : null,
                  enabled: !_saving,
                ),
                const SizedBox(height: 16),

                // ── Condition row ─────────────────────────────────────────────
                const Text('Condition',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textOnLight)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Field alias dropdown
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        value: _fieldAlias,
                        decoration: const InputDecoration(
                          labelText: 'Field',
                          border: OutlineInputBorder(),
                        ),
                        items: fieldOptions
                            .map((e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value.name,
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged:
                            _saving ? null : (v) => setState(() => _fieldAlias = v),
                        validator: (v) =>
                            v == null ? 'Select a field' : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Operator dropdown
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<AlertOperator>(
                        value: _operator,
                        decoration: const InputDecoration(
                          labelText: 'Operator',
                          border: OutlineInputBorder(),
                        ),
                        items: AlertOperator.values
                            .map((op) => DropdownMenuItem(
                                  value: op,
                                  child: Text(op.label),
                                ))
                            .toList(),
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _operator = v!),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Threshold
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _thresholdCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Threshold',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
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
                const SizedBox(height: 16),

                // ── Active time window ────────────────────────────────────────
                SwitchListTile(
                  value: _useTimeWindow,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _useTimeWindow = v),
                  title: const Text('Active only during time window'),
                  subtitle: const Text(
                      'Restrict the alert to specific hours (e.g. night time)',
                      style: TextStyle(fontSize: 12)),
                  contentPadding: EdgeInsets.zero,
                ),
                if (_useTimeWindow) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _timeStartCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Start (HH:mm)',
                            hintText: '22:00',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.schedule),
                          ),
                          validator: _useTimeWindow
                              ? (v) => _validateTime(v)
                              : null,
                          enabled: !_saving,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _timeEndCtrl,
                          decoration: const InputDecoration(
                            labelText: 'End (HH:mm)',
                            hintText: '06:00',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.schedule),
                          ),
                          validator: _useTimeWindow
                              ? (v) => _validateTime(v)
                              : null,
                          enabled: !_saving,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),

                // ── Who to notify ─────────────────────────────────────────────
                const Text('Who to Notify',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textOnLight)),
                const SizedBox(height: 8),
                if (_loadingMembers)
                  const Center(child: CircularProgressIndicator())
                else if (_members.isEmpty)
                  const Text(
                    'No members found in this organization.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  )
                else
                  ..._members.map((m) => CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(m['displayName'] as String),
                        subtitle: Text(m['email'] as String,
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textMuted)),
                        value: _selectedUserIds.contains(m['userId']),
                        onChanged: _saving
                            ? null
                            : (checked) {
                                setState(() {
                                  if (checked == true) {
                                    _selectedUserIds.add(m['userId'] as String);
                                  } else {
                                    _selectedUserIds
                                        .remove(m['userId'] as String);
                                  }
                                });
                              },
                      )),
                const SizedBox(height: 8),

                // ── Enabled switch ────────────────────────────────────────────
                SwitchListTile(
                  value: _enabled,
                  onChanged:
                      _saving ? null : (v) => setState(() => _enabled = v),
                  title: const Text('Enabled'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.textPrimary)),
                )
              : const Icon(Icons.save),
          label: Text(_saving ? 'Saving...' : (_isEdit ? 'Save' : 'Create')),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  String? _validateTime(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final parts = value.trim().split(':');
    if (parts.length != 2) return 'Use HH:mm format';
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return 'Invalid time';
    }
    return null;
  }
}
