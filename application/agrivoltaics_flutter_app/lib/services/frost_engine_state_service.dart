import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/frost_engine_state.dart';

/// Streams `frostEngineState/current` (plan §1c) for a zone — the singleton
/// runtime-state doc `functions/lib/frostEngine/evaluateZoneFrostEngine.js`
/// writes on every evaluation tick.
class FrostEngineStateService {
  const FrostEngineStateService();

  /// Emits `null` while no doc exists yet — either the zone's frost engine
  /// hasn't run a first tick, or `frostRuleConfig.enabled` is false. The
  /// panel is expected to show a "no data yet" placeholder in that case,
  /// and to pick up a manually-seeded doc live (useful for testing the
  /// display before real sensor data exists).
  Stream<FrostEngineState?> streamState({
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
        .doc(zoneId)
        .collection('frostEngineState')
        .doc('current')
        .snapshots()
        .map((snapshot) {
      final data = snapshot.data();
      if (data == null) return null;
      return FrostEngineState.fromMap(data);
    });
  }
}
