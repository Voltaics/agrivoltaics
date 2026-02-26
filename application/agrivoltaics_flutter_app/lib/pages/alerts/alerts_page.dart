import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_colors.dart';
import '../../app_state.dart';
import '../../models/alert_rule.dart';
import '../../services/alert_service.dart';
import '../../services/fcm_service.dart';
import '../../services/readings_service.dart';
import 'create_alert_rule_dialog.dart';

/// Top-level page for managing FCM alert rules for the selected organization.
///
/// Accessible from the sidebar / bottom nav under "Alerts".
class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  final AlertService _alertService = AlertService();
  final FcmService _fcmService = FcmService();
  final ReadingsService _readingsService = ReadingsService();

  bool _fcmGranted = false;
  bool _fcmChecked = false;

  @override
  void initState() {
    super.initState();
    _checkFcmStatus();
  }

  Future<void> _checkFcmStatus() async {
    final token = await _fcmService.getToken();
    if (mounted) {
      setState(() {
        _fcmGranted = token != null;
        _fcmChecked = true;
      });
    }
  }

  Future<void> _registerFcm() async {
    final granted = await _fcmService.requestPermissionAndSaveToken();
    if (mounted) {
      setState(() {
        _fcmGranted = granted;
      });
      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notification permission denied. '
                'Please allow notifications in your browser/device settings.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final org = appState.selectedOrganization;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header bar ──────────────────────────────────────────────────────
        _buildHeader(context, org?.id),

        // ── FCM registration banner ─────────────────────────────────────────
        if (_fcmChecked && !_fcmGranted) _buildFcmBanner(),

        // ── Alert rules list ────────────────────────────────────────────────
        Expanded(
          child: org == null
              ? _buildNoOrgState()
              : _buildRulesList(org.id),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, String? orgId) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_active, color: AppColors.primary),
          const SizedBox(width: 12),
          const Text(
            'Alert Rules',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textOnLight,
            ),
          ),
          const Spacer(),
          if (orgId != null)
            FilledButton.icon(
              onPressed: () => _openCreateDialog(context, orgId),
              icon: const Icon(Icons.add),
              label: const Text('New Alert'),
            ),
        ],
      ),
    );
  }

  Widget _buildFcmBanner() {
    return Material(
      color: AppColors.infoLight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.notifications_off_outlined, color: AppColors.info),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Push notifications are not enabled. '
                'Register to receive alerts on this device.',
                style: TextStyle(color: AppColors.textOnLight),
              ),
            ),
            TextButton(
              onPressed: _registerFcm,
              child: const Text('Enable Notifications'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoOrgState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.business_outlined, size: 64, color: AppColors.textMuted),
          SizedBox(height: 16),
          Text(
            'Select an organization to manage alert rules.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildRulesList(String orgId) {
    return StreamBuilder<List<AlertRule>>(
      stream: _alertService.getAlertRules(orgId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading alerts: ${snapshot.error}',
              style: const TextStyle(color: AppColors.error),
            ),
          );
        }

        final rules = snapshot.data ?? [];

        if (rules.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.notifications_none,
                    size: 64, color: AppColors.textMuted),
                const SizedBox(height: 16),
                const Text(
                  'No alert rules yet.',
                  style:
                      TextStyle(color: AppColors.textMuted, fontSize: 16),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _openCreateDialog(context, orgId),
                  icon: const Icon(Icons.add),
                  label: const Text('Create First Alert'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rules.length,
          itemBuilder: (context, index) =>
              _buildRuleCard(context, orgId, rules[index]),
        );
      },
    );
  }

  Widget _buildRuleCard(
      BuildContext context, String orgId, AlertRule rule) {
    final fieldName = _readingsService.getReadingName(rule.fieldAlias);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title row ──────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    rule.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textOnLight,
                    ),
                  ),
                ),
                // FCM register button if not enabled
                if (!_fcmGranted)
                  Tooltip(
                    message: 'Enable notifications to receive this alert',
                    child: TextButton.icon(
                      onPressed: _registerFcm,
                      icon: const Icon(Icons.notifications_off,
                          size: 16, color: AppColors.warning),
                      label: const Text(
                        'Register FCM',
                        style: TextStyle(
                            color: AppColors.warning, fontSize: 12),
                      ),
                    ),
                  ),
                Switch(
                  value: rule.enabled,
                  onChanged: (val) =>
                      _alertService.toggleAlertRule(orgId, rule.id, val),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ── Condition summary ──────────────────────────────────────────
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _chip(
                  Icons.sensors,
                  '$fieldName ${rule.operator.label} ${rule.threshold}',
                ),
                if (rule.activeTimeStart != null &&
                    rule.activeTimeEnd != null)
                  _chip(
                    Icons.schedule,
                    '${rule.activeTimeStart} – ${rule.activeTimeEnd}',
                  ),
                _chip(
                  Icons.people_outline,
                  '${rule.notifyUserIds.length} recipient'
                  '${rule.notifyUserIds.length == 1 ? '' : 's'}',
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ── Actions ────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () =>
                      _openEditDialog(context, orgId, rule),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () =>
                      _confirmDelete(context, orgId, rule),
                  icon: const Icon(Icons.delete_outline,
                      size: 16, color: AppColors.error),
                  label: const Text('Delete',
                      style: TextStyle(color: AppColors.error)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Chip(
      avatar: Icon(icon, size: 14, color: AppColors.primary),
      label: Text(label,
          style: const TextStyle(fontSize: 12, color: AppColors.textOnLight)),
      backgroundColor: AppColors.scaffoldBackground,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }

  Future<void> _openCreateDialog(BuildContext context, String orgId) async {
    await showDialog<void>(
      context: context,
      builder: (_) => CreateAlertRuleDialog(orgId: orgId),
    );
  }

  Future<void> _openEditDialog(
      BuildContext context, String orgId, AlertRule rule) async {
    await showDialog<void>(
      context: context,
      builder: (_) => CreateAlertRuleDialog(orgId: orgId, existingRule: rule),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, String orgId, AlertRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Alert Rule'),
        content: Text('Delete "${rule.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _alertService.deleteAlertRule(orgId, rule.id);
    }
  }
}
