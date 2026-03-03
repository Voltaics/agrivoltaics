import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/alert_rule.dart';

/// Service for managing [AlertRule] documents stored under
/// `organizations/{orgId}/alertRules/{ruleId}` in Firestore.
class AlertService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference _rulesRef(String orgId) =>
      _firestore.collection('organizations/$orgId/alertRules');

  // ── Streams ──────────────────────────────────────────────────────────────

  /// Stream all alert rules for [orgId], ordered by creation date.
  Stream<List<AlertRule>> getAlertRules(String orgId) {
    return _rulesRef(orgId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => AlertRule.fromFirestore(doc)).toList());
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  /// Create a new alert rule and return its generated ID.
  Future<String> createAlertRule({
    required String orgId,
    required String name,
    required String fieldAlias,
    required AlertOperator operator,
    required double threshold,
    bool enabled = true,
    List<String> notifyUserIds = const [],
    String? activeTimeStart,
    String? activeTimeEnd,
  }) async {
    final userId = _auth.currentUser!.uid;
    final ref = _rulesRef(orgId).doc();

    final rule = AlertRule(
      id: ref.id,
      name: name,
      fieldAlias: fieldAlias,
      operator: operator,
      threshold: threshold,
      enabled: enabled,
      notifyUserIds: notifyUserIds,
      activeTimeStart: activeTimeStart,
      activeTimeEnd: activeTimeEnd,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      createdBy: userId,
    );

    await ref.set(rule.toFirestore());
    return ref.id;
  }

  /// Update an existing alert rule (partial update).
  Future<void> updateAlertRule(
    String orgId,
    String ruleId,
    Map<String, dynamic> updates,
  ) async {
    await _rulesRef(orgId).doc(ruleId).update({
      ...updates,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Toggle the [enabled] flag of an alert rule.
  Future<void> toggleAlertRule(
    String orgId,
    String ruleId,
    bool enabled,
  ) async {
    await updateAlertRule(orgId, ruleId, {'enabled': enabled});
  }

  /// Delete an alert rule.
  Future<void> deleteAlertRule(String orgId, String ruleId) async {
    await _rulesRef(orgId).doc(ruleId).delete();
  }
}
