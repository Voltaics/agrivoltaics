import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/frost_rule_config.dart';
import 'organization_service.dart';

/// Reads/writes `frostRuleConfig` (plan §1b) on a zone document, and
/// records a `frostConfigAudit` entry (plan §1d) for each field that
/// actually changed, in the same write.
class FrostEngineConfigService {
  const FrostEngineConfigService();

  DocumentReference<Map<String, dynamic>> _zoneDoc({
    required String orgId,
    required String siteId,
    required String zoneId,
  }) {
    return FirebaseFirestore.instance
        .collection('organizations')
        .doc(orgId)
        .collection('sites')
        .doc(siteId)
        .collection('zones')
        .doc(zoneId);
  }

  Future<FrostRuleConfig> getFrostRuleConfig({
    required String orgId,
    required String siteId,
    required String zoneId,
  }) async {
    final snapshot = await _zoneDoc(
      orgId: orgId,
      siteId: siteId,
      zoneId: zoneId,
    ).get();

    final data = snapshot.data();
    final frostRuleConfig = data?['frostRuleConfig'];

    if (frostRuleConfig is Map<String, dynamic>) {
      return FrostRuleConfig.fromMap(frostRuleConfig);
    }

    if (frostRuleConfig is Map) {
      return FrostRuleConfig.fromMap(Map<String, dynamic>.from(frostRuleConfig));
    }

    return FrostRuleConfig.defaults();
  }

  /// Saves [updated] over [previous], merging into the zone doc's
  /// `frostRuleConfig` map and writing one `frostConfigAudit` doc per
  /// changed field, in a single batched write.
  Future<void> saveFrostRuleConfig({
    required String orgId,
    required String siteId,
    required String zoneId,
    required FrostRuleConfig previous,
    required FrostRuleConfig updated,
  }) async {
    if (!await OrganizationService().isMemberOfOrg(orgId)) {
      throw Exception('You are not a member of this organization.');
    }

    final changedByUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final zoneRef = _zoneDoc(orgId: orgId, siteId: siteId, zoneId: zoneId);
    final batch = FirebaseFirestore.instance.batch();

    batch.set(
      zoneRef,
      {
        'frostRuleConfig': {
          ...updated.toFirestoreMap(),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': changedByUid,
        },
      },
      SetOptions(merge: true),
    );

    final previousFields = previous.toFieldMap();
    final updatedFields = updated.toFieldMap();

    for (final key in updatedFields.keys) {
      final previousValue = previousFields[key];
      final newValue = updatedFields[key];

      if (previousValue == newValue) continue;

      final auditRef = zoneRef.collection('frostConfigAudit').doc();
      batch.set(auditRef, {
        'changedAt': FieldValue.serverTimestamp(),
        'changedByUid': changedByUid,
        'fieldKey': key,
        'previousValue': previousValue,
        'newValue': newValue,
        'cultivarAtChange': updated.cultivar,
        'growthStageAtChange': updated.growthStage,
      });
    }

    if (!_listEquals(previous.notifyUserIds, updated.notifyUserIds)) {
      final auditRef = zoneRef.collection('frostConfigAudit').doc();
      batch.set(auditRef, {
        'changedAt': FieldValue.serverTimestamp(),
        'changedByUid': changedByUid,
        'fieldKey': 'notifyUserIds',
        'previousValue': previous.notifyUserIds,
        'newValue': updated.notifyUserIds,
        'cultivarAtChange': updated.cultivar,
        'growthStageAtChange': updated.growthStage,
      });
    }

    await batch.commit();
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final sortedA = [...a]..sort();
    final sortedB = [...b]..sort();
    for (var i = 0; i < sortedA.length; i++) {
      if (sortedA[i] != sortedB[i]) return false;
    }
    return true;
  }
}
