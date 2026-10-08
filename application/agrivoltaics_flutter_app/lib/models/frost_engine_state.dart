import 'package:cloud_firestore/cloud_firestore.dart';

/// Parses `frostEngineState/current`
/// (`organizations/{orgId}/sites/{siteId}/zones/{zoneId}/frostEngineState/current`),
/// the singleton runtime-state doc the Cloud Functions engine
/// (`functions/lib/frostEngine/stateStore.js`) writes on every evaluation
/// tick and the Flutter panel streams directly.
///
/// Most timestamp-shaped fields here (`levelEnteredAt`, `lastEvalIso`,
/// `ruleStreaks[*].lastTrueAt/lastEvalAt`, `leafWetness.stateSince`,
/// `eventAccumulators.firstBelowCriticalAt`) are written server-side as
/// plain ISO-8601 strings (`now.toISOString()`), **not** Firestore
/// `Timestamp`s — only `updatedAt` (added by `saveEngineState` via
/// `FieldValue.serverTimestamp()`) is a real `Timestamp`. `_dateFromValue`
/// below accepts either shape so this model doesn't have to track which is
/// which per field.
class RuleStreak {
  const RuleStreak({
    required this.consecutiveTrue,
    this.lastTrueAt,
    this.lastEvalAt,
  });

  final int consecutiveTrue;
  final DateTime? lastTrueAt;
  final DateTime? lastEvalAt;

  factory RuleStreak.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const {};
    return RuleStreak(
      consecutiveTrue: _intFromValue(map['consecutiveTrue']) ?? 0,
      lastTrueAt: _dateFromValue(map['lastTrueAt']),
      lastEvalAt: _dateFromValue(map['lastEvalAt']),
    );
  }
}

class LeafWetnessState {
  const LeafWetnessState({
    required this.rawValue,
    required this.state,
    required this.stateSince,
    required this.continuousWetnessMinutes,
    required this.justTransitionedDryToWet,
  });

  final double? rawValue;
  final String state; // 'wet' | 'dry'
  final DateTime? stateSince;
  final double continuousWetnessMinutes;
  final bool justTransitionedDryToWet;

  bool get isWet => state == 'wet';

  factory LeafWetnessState.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const {};
    return LeafWetnessState(
      rawValue: _doubleFromValue(map['rawValue']),
      state: map['state'] is String ? map['state'] as String : 'dry',
      stateSince: _dateFromValue(map['stateSince']),
      continuousWetnessMinutes: _doubleFromValue(map['continuousWetnessMinutes']) ?? 0,
      justTransitionedDryToWet: map['justTransitionedDryToWet'] == true,
    );
  }
}

class FrostEventAccumulators {
  const FrostEventAccumulators({
    required this.minTempF,
    required this.timeBelowCriticalMinutes,
    required this.timeBelow32Minutes,
    required this.timeBelow30Minutes,
    required this.maxCoolingRateFPerHr,
    required this.firstBelowCriticalAt,
    required this.recoveryStableMinutes,
  });

  final double? minTempF;
  final double timeBelowCriticalMinutes;
  final double timeBelow32Minutes;
  final double timeBelow30Minutes;
  final double? maxCoolingRateFPerHr;
  final DateTime? firstBelowCriticalAt;
  final double recoveryStableMinutes;

  factory FrostEventAccumulators.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const {};
    return FrostEventAccumulators(
      minTempF: _doubleFromValue(map['minTempF']),
      timeBelowCriticalMinutes: _doubleFromValue(map['timeBelowCriticalMinutes']) ?? 0,
      timeBelow32Minutes: _doubleFromValue(map['timeBelow32Minutes']) ?? 0,
      timeBelow30Minutes: _doubleFromValue(map['timeBelow30Minutes']) ?? 0,
      maxCoolingRateFPerHr: _doubleFromValue(map['maxCoolingRateFPerHr']),
      firstBelowCriticalAt: _dateFromValue(map['firstBelowCriticalAt']),
      recoveryStableMinutes: _doubleFromValue(map['recoveryStableMinutes']) ?? 0,
    );
  }
}

class FrostFieldQuality {
  const FrostFieldQuality({
    required this.stale,
    required this.lastGoodAt,
    required this.missedIntervals,
  });

  final bool stale;
  final DateTime? lastGoodAt;
  final int missedIntervals;

  factory FrostFieldQuality.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const {};
    return FrostFieldQuality(
      stale: map['stale'] == true,
      lastGoodAt: _dateFromValue(map['lastGoodAt']),
      missedIntervals: _intFromValue(map['missedIntervals']) ?? 0,
    );
  }
}

class FrostDataQuality {
  const FrostDataQuality({
    required this.temperature,
    required this.humidity,
    required this.windSpeed,
    required this.leafMoisture,
    required this.overallFlag,
  });

  final FrostFieldQuality temperature;
  final FrostFieldQuality humidity;
  final FrostFieldQuality windSpeed;
  final FrostFieldQuality leafMoisture;

  /// 'ok' | 'stale' | 'sensor_unavailable'
  final String overallFlag;

  bool get isOk => overallFlag == 'ok';

  factory FrostDataQuality.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const {};
    return FrostDataQuality(
      temperature: FrostFieldQuality.fromMap(_asStringKeyedMap(map['temperature'])),
      humidity: FrostFieldQuality.fromMap(_asStringKeyedMap(map['humidity'])),
      windSpeed: FrostFieldQuality.fromMap(_asStringKeyedMap(map['windSpeed'])),
      leafMoisture: FrostFieldQuality.fromMap(_asStringKeyedMap(map['leafMoisture'])),
      overallFlag: map['overallFlag'] is String ? map['overallFlag'] as String : 'ok',
    );
  }
}

class FrostDerivedSnapshot {
  const FrostDerivedSnapshot({
    required this.airTempF,
    required this.dewPointF,
    required this.dewPointSpreadF,
    required this.coolingRate15FPerHr,
    required this.coolingRate60FPerHr,
    required this.projectedTemp2hF,
    required this.windSpeedMph,
    required this.windClass,
    required this.windClassLabel,
    required this.continuousWetnessMinutes,
  });

  final double? airTempF;
  final double? dewPointF;
  final double? dewPointSpreadF;
  final double? coolingRate15FPerHr;
  final double? coolingRate60FPerHr;
  final double? projectedTemp2hF;
  final double? windSpeedMph;
  final String? windClass; // calm|light|moderate|strong
  final String? windClassLabel;
  final double continuousWetnessMinutes;

  factory FrostDerivedSnapshot.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const {};
    return FrostDerivedSnapshot(
      airTempF: _doubleFromValue(map['airTempF']),
      dewPointF: _doubleFromValue(map['dewPointF']),
      dewPointSpreadF: _doubleFromValue(map['dewPointSpreadF']),
      coolingRate15FPerHr: _doubleFromValue(map['coolingRate15FPerHr']),
      coolingRate60FPerHr: _doubleFromValue(map['coolingRate60FPerHr']),
      projectedTemp2hF: _doubleFromValue(map['projectedTemp2hF']),
      windSpeedMph: _doubleFromValue(map['windSpeedMph']),
      windClass: map['windClass'] is String ? map['windClass'] as String : null,
      windClassLabel: map['windClassLabel'] is String ? map['windClassLabel'] as String : null,
      continuousWetnessMinutes: _doubleFromValue(map['continuousWetnessMinutes']) ?? 0,
    );
  }
}

/// Alert-level rank, mirroring `LEVEL_RANK` in `functions/lib/frostEngine/rules.js`.
/// `allClear` is intentionally excluded — it's a recovery state reached only
/// via an explicit All-Clear pass, not part of the monotonic ladder.
const Map<String, int> kFrostLevelRank = {
  'normal': 0,
  'watch': 1,
  'warning': 2,
  'imminent': 3,
  'event': 4,
};

class FrostEngineState {
  const FrostEngineState({
    required this.currentLevel,
    required this.previousLevel,
    required this.activeSubWarning,
    required this.levelEnteredAt,
    required this.lastNotifiedLevel,
    required this.ruleStreaks,
    required this.leafWetness,
    required this.eventAccumulators,
    required this.postEventLog,
    required this.dataQuality,
    required this.derivedSnapshot,
    required this.lastEvalIso,
    required this.updatedAt,
  });

  /// normal|watch|warning|imminent|event|allClear
  final String currentLevel;
  final String? previousLevel;

  /// radiation|advective|mixed|null
  final String? activeSubWarning;
  final DateTime? levelEnteredAt;
  final String? lastNotifiedLevel;
  final Map<String, RuleStreak> ruleStreaks;
  final LeafWetnessState leafWetness;
  final FrostEventAccumulators eventAccumulators;
  final FrostEventAccumulators? postEventLog;
  final FrostDataQuality dataQuality;
  final FrostDerivedSnapshot derivedSnapshot;

  /// Timestamp of the last evaluation tick that actually ran (skipped/throttled
  /// ticks don't advance this) — distinct from `updatedAt`, which is the
  /// Firestore write time of this doc.
  final DateTime? lastEvalIso;
  final DateTime? updatedAt;

  factory FrostEngineState.fromMap(Map<String, dynamic> data) {
    final ruleStreaksMap = _asStringKeyedMap(data['ruleStreaks']) ?? const {};

    return FrostEngineState(
      currentLevel: data['currentLevel'] is String ? data['currentLevel'] as String : 'normal',
      previousLevel: data['previousLevel'] is String ? data['previousLevel'] as String : null,
      activeSubWarning: data['activeSubWarning'] is String ? data['activeSubWarning'] as String : null,
      levelEnteredAt: _dateFromValue(data['levelEnteredAt']),
      lastNotifiedLevel: data['lastNotifiedLevel'] is String ? data['lastNotifiedLevel'] as String : null,
      ruleStreaks: ruleStreaksMap.map(
        (key, value) => MapEntry(key, RuleStreak.fromMap(_asStringKeyedMap(value))),
      ),
      leafWetness: LeafWetnessState.fromMap(_asStringKeyedMap(data['leafWetness'])),
      eventAccumulators: FrostEventAccumulators.fromMap(_asStringKeyedMap(data['eventAccumulators'])),
      postEventLog: data['postEventLog'] == null
          ? null
          : FrostEventAccumulators.fromMap(_asStringKeyedMap(data['postEventLog'])),
      dataQuality: FrostDataQuality.fromMap(_asStringKeyedMap(data['dataQuality'])),
      derivedSnapshot: FrostDerivedSnapshot.fromMap(_asStringKeyedMap(data['derivedSnapshot'])),
      lastEvalIso: _dateFromValue(data['lastEvalIso']),
      updatedAt: _dateFromValue(data['updatedAt']),
    );
  }
}

Map<String, dynamic>? _asStringKeyedMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

double? _doubleFromValue(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _intFromValue(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

DateTime? _dateFromValue(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
