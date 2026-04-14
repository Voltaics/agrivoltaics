import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/alert_rule.dart';

class AlertService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference _rulesRef(String orgId) =>
      _firestore.collection('organizations/$orgId/alertRules');

  Stream<List<AlertRule>> getAlertRules(String orgId) {
    return _rulesRef(orgId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => AlertRule.fromFirestore(doc)).toList());
  }

  Future<String> createAlertRule({
    required String orgId,
    required Map<String, dynamic> payload,
  }) async {
    final userId = _auth.currentUser!.uid;
    final ref = _rulesRef(orgId).doc();

    await ref.set({
      ...payload,
      'id': ref.id,
      'createdBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return ref.id;
  }

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

  Future<void> toggleAlertRule(
    String orgId,
    String ruleId,
    bool enabled,
  ) async {
    await updateAlertRule(orgId, ruleId, {'enabled': enabled});
  }

  Future<void> deleteAlertRule(String orgId, String ruleId) async {
    await _rulesRef(orgId).doc(ruleId).delete();
  }
}