import 'package:cloud_firestore/cloud_firestore.dart';

class FrostSettings {
  const FrostSettings({
    required this.enabled,
    required this.predStart,
    required this.predEnd,
    required this.tempThresholdF,
  });

  final bool enabled;
  final DateTime predStart;
  final DateTime predEnd;
  final int tempThresholdF;

  factory FrostSettings.fromMap(Map<String, dynamic>? data) {
    final now = DateTime.now();

    if (data == null) {
      return FrostSettings(
        enabled: true,
        predStart: now,
        predEnd: now.add(const Duration(days: 3)),
        tempThresholdF: 40,
      );
    }

    return FrostSettings(
      enabled: data['enabled'] == true,
      predStart: _dateFromValue(data['predStart']) ?? now,
      predEnd: _dateFromValue(data['predEnd']) ?? now.add(const Duration(days: 3)),
      tempThresholdF: _intFromValue(data['tempThresholdF']) ?? 40,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'enabled': enabled,
      'predStart': Timestamp.fromDate(predStart),
      'predEnd': Timestamp.fromDate(predEnd),
      'tempThresholdF': tempThresholdF,
    };
  }

  static DateTime? _dateFromValue(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static int? _intFromValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

class FrostSettingsService {
  const FrostSettingsService();

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

  Future<FrostSettings> getFrostSettings({
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
    final frostSettings = data?['frostSettings'];

    if (frostSettings is Map<String, dynamic>) {
      return FrostSettings.fromMap(frostSettings);
    }

    if (frostSettings is Map) {
      return FrostSettings.fromMap(Map<String, dynamic>.from(frostSettings));
    }

    return FrostSettings.fromMap(null);
  }

  Future<void> saveFrostSettings({
    required String orgId,
    required String siteId,
    required String zoneId,
    required FrostSettings settings,
  }) async {
    await _zoneDoc(
      orgId: orgId,
      siteId: siteId,
      zoneId: zoneId,
    ).set(
      {
        'frostSettings': settings.toFirestoreMap(),
      },
      SetOptions(merge: true),
    );
  }
}