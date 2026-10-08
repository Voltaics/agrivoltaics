import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrivoltaics_flutter_app/models/frost_engine_state.dart';

void main() {
  group('FrostEngineState.fromMap', () {
    test('parses a fully-populated doc as written by evaluateZoneFrostEngine.js', () {
      final state = FrostEngineState.fromMap({
        'currentLevel': 'warning',
        'previousLevel': 'watch',
        'activeSubWarning': 'radiation',
        // Written server-side as a plain ISO string (now.toISOString()), not a Timestamp.
        'levelEnteredAt': '2026-08-14T05:00:00.000Z',
        'lastNotifiedLevel': 'watch',
        'ruleStreaks': {
          'rule3A': {'consecutiveTrue': 2, 'lastTrueAt': '2026-08-14T05:00:00.000Z', 'lastEvalAt': '2026-08-14T05:00:00.000Z'},
          'rule3B': {'consecutiveTrue': 0, 'lastTrueAt': null, 'lastEvalAt': '2026-08-14T05:00:00.000Z'},
          'rule3C': {'consecutiveTrue': 0, 'lastTrueAt': null, 'lastEvalAt': null},
        },
        'leafWetness': {
          'rawValue': 46.0,
          'state': 'wet',
          'stateSince': '2026-08-14T04:14:00.000Z',
          'continuousWetnessMinutes': 46.0,
          'justTransitionedDryToWet': false,
        },
        'eventAccumulators': {
          'minTempF': 34.1,
          'timeBelowCriticalMinutes': 0,
          'timeBelow32Minutes': 0,
          'timeBelow30Minutes': 0,
          'maxCoolingRateFPerHr': -1.8,
          'firstBelowCriticalAt': null,
          'recoveryStableMinutes': 0,
        },
        'postEventLog': null,
        'dataQuality': {
          'temperature': {'stale': false, 'lastGoodAt': '2026-08-14T05:00:00.000Z', 'missedIntervals': 0},
          'humidity': {'stale': false, 'lastGoodAt': '2026-08-14T05:00:00.000Z', 'missedIntervals': 0},
          'windSpeed': {'stale': false, 'lastGoodAt': '2026-08-14T05:00:00.000Z', 'missedIntervals': 0},
          'leafMoisture': {'stale': false, 'lastGoodAt': '2026-08-14T05:00:00.000Z', 'missedIntervals': 0},
          'overallFlag': 'ok',
        },
        'derivedSnapshot': {
          'airTempF': 34.8,
          'dewPointF': 34.1,
          'dewPointSpreadF': 0.7,
          'coolingRate15FPerHr': -1.6,
          'coolingRate60FPerHr': -1.8,
          'projectedTemp2hF': 31.2,
          'windSpeedMph': 1.8,
          'windClass': 'calm',
          'windClassLabel': 'Calm - strong radiation-frost potential',
          'continuousWetnessMinutes': 46.0,
        },
        // Also a plain ISO string server-side.
        'lastEvalIso': '2026-08-14T05:00:00.000Z',
        // The one field that IS a real Firestore Timestamp (FieldValue.serverTimestamp()).
        'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 14, 5, 0, 1)),
      });

      expect(state.currentLevel, 'warning');
      expect(state.activeSubWarning, 'radiation');
      expect(state.levelEnteredAt, DateTime.utc(2026, 8, 14, 5, 0));
      expect(state.ruleStreaks['rule3A']!.consecutiveTrue, 2);
      expect(state.ruleStreaks['rule3B']!.lastTrueAt, isNull);
      expect(state.leafWetness.isWet, isTrue);
      expect(state.leafWetness.continuousWetnessMinutes, 46.0);
      expect(state.eventAccumulators.maxCoolingRateFPerHr, -1.8);
      expect(state.postEventLog, isNull);
      expect(state.dataQuality.isOk, isTrue);
      expect(state.derivedSnapshot.airTempF, 34.8);
      expect(state.derivedSnapshot.windClassLabel, 'Calm - strong radiation-frost potential');
      expect(state.lastEvalIso, DateTime.utc(2026, 8, 14, 5, 0));
      // Timestamp.toDate() returns a DateTime in the local time zone (same
      // instant, different representation) — normalize before comparing.
      expect(state.updatedAt!.toUtc(), DateTime.utc(2026, 8, 14, 5, 0, 1));
    });

    test('a minimally-seeded doc (manual Firestore console test) falls back sensibly', () {
      final state = FrostEngineState.fromMap({'currentLevel': 'normal'});

      expect(state.currentLevel, 'normal');
      expect(state.previousLevel, isNull);
      expect(state.leafWetness.state, 'dry');
      expect(state.leafWetness.isWet, isFalse);
      expect(state.dataQuality.overallFlag, 'ok');
      expect(state.derivedSnapshot.airTempF, isNull);
      expect(state.ruleStreaks, isEmpty);
    });

    test('overallFlag sensor_unavailable is preserved from a stale-temperature doc', () {
      final state = FrostEngineState.fromMap({
        'currentLevel': 'warning',
        'dataQuality': {
          'temperature': {'stale': true, 'lastGoodAt': null, 'missedIntervals': 2},
          'overallFlag': 'sensor_unavailable',
        },
      });

      expect(state.dataQuality.isOk, isFalse);
      expect(state.dataQuality.overallFlag, 'sensor_unavailable');
      expect(state.dataQuality.temperature.stale, isTrue);
    });
  });

  test('kFrostLevelRank matches functions/lib/frostEngine/rules.js LEVEL_RANK', () {
    expect(kFrostLevelRank['normal'], 0);
    expect(kFrostLevelRank['watch'], 1);
    expect(kFrostLevelRank['warning'], 2);
    expect(kFrostLevelRank['imminent'], 3);
    expect(kFrostLevelRank['event'], 4);
    expect(kFrostLevelRank.containsKey('allClear'), isFalse);
  });
}
