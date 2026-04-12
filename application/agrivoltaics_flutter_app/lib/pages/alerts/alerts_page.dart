import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
    // Use getNotificationSettings() so this works regardless of VAPID key.
    final granted = await _fcmService.checkPermissionStatus();
    if (mounted) {
      setState(() {
        _fcmGranted = granted;
        _fcmChecked = true;
      });
    }
  }

  String _buildConditionLabel(AlertRule rule) {
    final config = rule.ruleConfig ?? {};

    if (rule.ruleType == AlertRuleType.frostWarning) {
      final drop = config['tempDropRateFPerHour'] ?? 2.0;
      final humidity = config['humidityMin'] ?? 90.0;
      final air = config['airTempMaxF'] ?? 39.0;
      final soil = config['soilTempMaxF'] ?? 45.0;
      return 'Frost: drop > $drop°F/hr, RH ≥ $humidity%, air ≤ $air°F, soil ≤ $soil°F';
    }

    if (rule.ruleType == AlertRuleType.moldRisk) {
      final humidity = config['humidityMin'] ?? 85.0;
      final tempMin = config['tempMinF'] ?? 68.0;
      final tempMax = config['tempMaxF'] ?? 86.0;
      final hours = config['durationHours'] ?? 6.0;
      return 'Mold: RH ≥ $humidity% for $hours hr, temp $tempMin\u2013$tempMax°F';
    }

    if (rule.ruleType == AlertRuleType.blackRotRisk) {
      final humidity = config['humidityMin'] ?? 90.0;
      final tempMin = config['tempMinF'] ?? 70.0;
      final tempMax = config['tempMaxF'] ?? 85.0;
      final hours = config['followupHours'] ?? 48.0;
      return 'Black rot: RH ≥ $humidity%, temp $tempMin\u2013$tempMax°F, humid follow-up $hours hr';
    }

    final fieldName = _readingsService.getReadingName(rule.fieldAlias);
    final operatorLabel = rule.operator?.label ?? '?';
    final thresholdLabel = rule.threshold?.toString() ?? '?';
    return '$fieldName $operatorLabel $thresholdLabel';
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
        //  Header bar 
        _buildHeader(context, org?.id),

        //  FCM registration banner 
        if (_fcmChecked && !_fcmGranted) _buildFcmBanner(),

        //  Alert rules list 
        Expanded(
          child: org == null
              ? _buildNoOrgState()
              : _buildRulesList(org.id),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, String? orgId) {
    final isCompact = MediaQuery.of(context).size.width < 640;

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
      child: isCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.notifications_active, color: AppColors.primary),
                    SizedBox(width: 12),
                    Text(
                      'Alert Rules',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textOnLight,
                      ),
                    ),
                  ],
                ),
                if (orgId != null) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _openCreateDialog(context, orgId),
                    icon: const Icon(Icons.add),
                    label: const Text('New Alert'),
                  ),
                ],
              ],
            )
          : Row(
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
    final screenWidth = MediaQuery.of(context).size.width;
    final useDesktopGrid = screenWidth >= 1280;

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

        if (!useDesktopGrid) {
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rules.length,
            itemBuilder: (context, index) =>
                _buildRuleCard(context, orgId, rules[index]),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rules.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 560,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.45,
          ),
          itemBuilder: (context, index) =>
              _buildRuleCard(context, orgId, rules[index]),
        );
      },
    );
  }

  Widget _buildRuleCard(
      BuildContext context, String orgId, AlertRule rule) {
    final conditionLabel = _buildConditionLabel(rule);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            //  Title row 
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

            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _chip(Icons.rule, conditionLabel),
                if (rule.activeRangeStart != null &&
                    rule.activeRangeEnd != null)
                  _chip(
                    Icons.schedule,
                    '${rule.activeRangeStart} \u2013 ${rule.activeRangeEnd}',
                  ),
                _chip(
                  Icons.people_outline,
                  '${rule.notifyUserIds.length} recipient'
                  '${rule.notifyUserIds.length == 1 ? '' : 's'}',
                ),
              ],
            ),
            const SizedBox(height: 8),

            //  Actions 
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _sendTestAlert(context, orgId, rule),
                  icon: const Icon(Icons.send_outlined,
                      size: 16, color: AppColors.primary),
                  label: const Text('Test'),
                ),
                const SizedBox(width: 4),
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

  static const _testAlertUrl =
      'https://us-central1-agrivoltaics-flutter-firebase.cloudfunctions.net/sendTestAlert';

  Future<void> _sendTestAlert(
      BuildContext context, String orgId, AlertRule rule) async {
    final messenger = ScaffoldMessenger.of(context);
    String? token;
    try {
      token = await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Auth error: $e'),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    if (token == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Not signed in.'),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    messenger.showSnackBar(const SnackBar(
      content: Text('Sending test alert…'),
      duration: Duration(seconds: 2),
    ));
    try {
      final resp = await http.post(
        Uri.parse(_testAlertUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: '{"orgId":"$orgId","ruleId":"${rule.id}"}',
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final notified = data['notified'] as int? ?? 0;
        final msg = notified > 0
            ? 'Test alert sent — notified $notified member${notified == 1 ? '' : 's'}'
            : 'Sent, but found 0 org members — check Firestore members subcollection';
        messenger.showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: notified > 0 ? AppColors.primary : AppColors.warning,
        ));
      } else {
        messenger.showSnackBar(SnackBar(
          content: Text('Error ${resp.statusCode}: ${resp.body}'),
          backgroundColor: AppColors.error,
        ));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Failed: $e'),
        backgroundColor: AppColors.error,
      ));
    }
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
