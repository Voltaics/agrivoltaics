import 'package:flutter_test/flutter_test.dart';

import 'package:agrivoltaics_flutter_app/models/frost_rule_config.dart';
import 'package:agrivoltaics_flutter_app/pages/analytics/models/frost_alert_state/config/frost_engine_config_field_specs.dart';

void main() {
  group('FrostRuleConfig', () {
    test('defaults match the spec-faithful fallbacks used by the Cloud Functions engine', () {
      final config = FrostRuleConfig.defaults();

      expect(config.enabled, isFalse);
      expect(config.growthStage, 'dormant');
      expect(config.criticalTempF, 32);
      expect(config.minExposureDurationMinutes, 30);
      expect(config.eventMarginF, 2);
      expect(config.allClearHoldMinutes, 60);
      expect(config.warningMinConsecutiveReadings, 2);
      expect(config.windCalmMaxMph, 2);
      expect(config.leafWetnessDryMaxPercent, 20);
      expect(config.leafWetnessWetMinPercent, 30);
      expect(config.watch2A_coolingRateMinFPerHr, -2);
      expect(config.imminent4A_minGrowthStage, 'budBreak');
      expect(config.frostSensitiveFromStage, 'swollenBud');
      expect(config.nightLightMaxLux, 5000);
      expect(config.notifyUserIds, isEmpty);
    });

    test('round-trips through toFirestoreMap/fromMap without losing values', () {
      final original = FrostRuleConfig.fromMap({
        'enabled': true,
        'growthStage': 'flowering',
        'cultivar': 'Chambourcin',
        'criticalTempF': 30,
        'watch2A_coolingRateMinFPerHr': -1.5,
        'notifyUserIds': ['user-1', 'user-2'],
      });

      final roundTripped = FrostRuleConfig.fromMap(original.toFirestoreMap());

      expect(roundTripped.enabled, isTrue);
      expect(roundTripped.growthStage, 'flowering');
      expect(roundTripped.cultivar, 'Chambourcin');
      expect(roundTripped.criticalTempF, 30);
      expect(roundTripped.watch2A_coolingRateMinFPerHr, -1.5);
      expect(roundTripped.notifyUserIds, ['user-1', 'user-2']);
    });

    test('an unknown/missing growth stage falls back to a valid default rather than an empty string', () {
      final config = FrostRuleConfig.fromMap({'growthStage': ''});
      expect(config.growthStage, 'dormant');
    });
  });

  group('frostConfigFieldSpecs', () {
    test('every generic field key matches a FrostRuleConfig.toFieldMap() key exactly', () {
      // Guards against a typo silently dropping a threshold from the
      // generated form, or the form editing a key the engine never reads.
      expect(frostConfigFieldSpecKeysMatchModel(), isTrue);
    });

    test('field keys are unique', () {
      final keys = frostConfigFieldSpecs.map((s) => s.key).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('every field belongs to a group in frostConfigGroupOrder', () {
      for (final spec in frostConfigFieldSpecs) {
        expect(frostConfigGroupOrder, contains(spec.group));
      }
    });
  });
}
