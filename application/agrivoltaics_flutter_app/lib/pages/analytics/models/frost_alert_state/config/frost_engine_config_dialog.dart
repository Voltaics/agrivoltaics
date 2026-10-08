import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../../app_colors.dart';
import '../../../../../models/frost_rule_config.dart';
import '../../../../../services/frost_engine_config_service.dart';
import 'frost_engine_config_form_builder.dart';

/// Zone-scoped editor for `frostRuleConfig` (plan §1b) — the farmer-facing
/// settings surface for the six-level frost engine. Meant to be opened from
/// a gear icon on the zone's frost-alert-state display panel (plan §3/§4),
/// the same way `frost_settings_dialog.dart` is opened from the frost
/// prediction timeline panel.
class FrostEngineConfigDialog extends StatefulWidget {
  const FrostEngineConfigDialog({
    super.key,
    required this.orgId,
    required this.siteId,
    required this.zoneId,
    this.zoneName,
  });

  final String orgId;
  final String siteId;
  final String zoneId;
  final String? zoneName;

  @override
  State<FrostEngineConfigDialog> createState() => _FrostEngineConfigDialogState();
}

class _FrostEngineConfigDialogState extends State<FrostEngineConfigDialog> {
  final _formKey = GlobalKey<FormState>();
  final _configService = const FrostEngineConfigService();
  late final TextEditingController _cultivarCtrl;

  FrostRuleConfig? _loadedConfig;
  Map<String, dynamic> _draftFields = {};
  bool _enabled = false;
  final Set<String> _selectedNotifyUserIds = {};

  List<Map<String, dynamic>> _members = [];
  bool _loadingMembers = true;

  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _cultivarCtrl = TextEditingController();
    _loadConfig();
    _loadMembers();
  }

  @override
  void dispose() {
    _cultivarCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final config = await _configService.getFrostRuleConfig(
        orgId: widget.orgId,
        siteId: widget.siteId,
        zoneId: widget.zoneId,
      );

      if (!mounted) return;

      setState(() {
        _loadedConfig = config;
        _draftFields = config.toFieldMap();
        _enabled = config.enabled;
        _cultivarCtrl.text = config.cultivar;
        _selectedNotifyUserIds
          ..clear()
          ..addAll(config.notifyUserIds);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Error loading frost engine config: $e';
      });
    }
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
    final loadedConfig = _loadedConfig;
    if (loadedConfig == null) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final finalConfig = FrostRuleConfig.fromMap({
      ...loadedConfig.toFirestoreMap(),
      ..._draftFields,
      'enabled': _enabled,
      'cultivar': _cultivarCtrl.text.trim(),
      'notifyUserIds': _selectedNotifyUserIds.toList(),
    });

    try {
      await _configService.saveFrostRuleConfig(
        orgId: widget.orgId,
        siteId: widget.siteId,
        zoneId: widget.zoneId,
        previous: loadedConfig,
        updated: finalConfig,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving frost engine config: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isDesktop = media.size.width >= 1280;
    final maxDialogWidth = media.size.width * 0.95;
    final preferredWidth = isDesktop ? 760.0 : 560.0;
    final dialogWidth = maxDialogWidth > preferredWidth ? preferredWidth : maxDialogWidth;
    final verticalInset = isDesktop ? 24.0 : 12.0;
    final maxDialogHeight = media.size.height * (isDesktop ? 0.9 : 0.86);

    final title = widget.zoneName == null
        ? 'Frost Engine Rules'
        : 'Frost Engine Rules — ${widget.zoneName}';

    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: verticalInset),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogWidth, maxHeight: maxDialogHeight),
        child: SizedBox(
          width: dialogWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Row(
                  children: [
                    const Icon(Icons.ac_unit, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              Expanded(child: _buildBody()),
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
                      onPressed: _saving || _loading || _loadedConfig == null ? null : _save,
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

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(_loadError!, style: const TextStyle(color: AppColors.error)),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                value: _enabled,
                onChanged: _saving ? null : (value) => setState(() => _enabled = value),
                title: const Text('Enabled'),
                subtitle: const Text(
                  'Turns the six-level frost engine on for this zone. Runs alongside, and independently of, the existing frost warning alert and AI prediction.',
                ),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cultivarCtrl,
                autofillHints: const [],
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Cultivar',
                  border: OutlineInputBorder(),
                  helperText: 'Recorded on every config-change audit entry for this zone.',
                ),
              ),
              const SizedBox(height: 16),
              FrostEngineConfigFormBuilder(
                key: ValueKey('${widget.orgId}::${widget.siteId}::${widget.zoneId}'),
                initialValues: _draftFields,
                enabled: !_saving,
                onFieldChanged: (key, value) => _draftFields[key] = value,
              ),
              const SizedBox(height: 16),
              const Text(
                'Who to Notify',
                style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textOnLight),
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
                    value: _selectedNotifyUserIds.contains(m['userId']),
                    onChanged: _saving
                        ? null
                        : (checked) {
                            setState(() {
                              if (checked == true) {
                                _selectedNotifyUserIds.add(m['userId'] as String);
                              } else {
                                _selectedNotifyUserIds.remove(m['userId'] as String);
                              }
                            });
                          },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
