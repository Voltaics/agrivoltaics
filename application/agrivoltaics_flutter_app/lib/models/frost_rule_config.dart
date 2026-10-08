import 'package:cloud_firestore/cloud_firestore.dart';

/// Ordered grapevine growth stages, dormant (least sensitive) to fruit set.
///
/// Mirrors `functions/lib/frostEngine/utils.js`'s `GROWTH_STAGES` exactly —
/// keep these two lists in sync by hand (no shared schema layer exists
/// between the Cloud Functions and Flutter codebases).
const List<String> kFrostGrowthStages = [
  'dormant',
  'swollenBud',
  'budBreak',
  'shoot1to3in',
  'flowering',
  'fruitSet',
];

const Map<String, String> kFrostGrowthStageLabels = {
  'dormant': 'Dormant',
  'swollenBud': 'Swollen Bud',
  'budBreak': 'Bud Break',
  'shoot1to3in': 'Shoot 1–3 in',
  'flowering': 'Flowering',
  'fruitSet': 'Fruit Set',
};

String frostGrowthStageLabel(String stage) =>
    kFrostGrowthStageLabels[stage] ?? stage;

/// Typed model for the `frostRuleConfig` map on a zone document
/// (`organizations/{orgId}/sites/{siteId}/zones/{zoneId}`).
///
/// Every default below must match the corresponding `defaultIfNull(config.*, ...)`
/// fallback in `functions/lib/frostEngine/{derivations,rules,evaluateZoneFrostEngine}.js` —
/// there is no shared schema layer, so these are kept in sync manually, the
/// same situation as today's duplicated `frostSettings.tempThresholdF: 40` default.
class FrostRuleConfig {
  const FrostRuleConfig({
    required this.enabled,
    required this.growthStage,
    required this.cultivar,
    required this.criticalTempF,
    required this.minExposureDurationMinutes,
    required this.eventMarginF,
    required this.allClearMarginF,
    required this.allClearStableMinutes,
    required this.allClearForecastWindowHours,
    required this.allClearHoldMinutes,
    required this.warningMinConsecutiveReadings,
    required this.windCalmMaxMph,
    required this.windLightMaxMph,
    required this.windModerateMaxMph,
    required this.leafWetnessDryMaxPercent,
    required this.leafWetnessWetMinPercent,
    required this.watch2A_airTempMaxF,
    required this.watch2A_coolingRateMinFPerHr,
    required this.watch2A_windMaxMph,
    required this.watch2A_dewSpreadMinF,
    required this.watch2B_forecastHorizonHours,
    required this.watch2B_referenceThresholdF,
    required this.warn3A_airTempMaxF,
    required this.warn3A_windMaxMph,
    required this.warn3A_coolingRateMinFPerHr,
    required this.warn3A_dewSpreadMaxF,
    required this.warn3B_airTempMaxF,
    required this.warn3B_windMaxMph,
    required this.warn3B_coolingRateMinFPerHr,
    required this.warn3B_dewSpreadMinF,
    required this.warn3B_projected2hMaxF,
    required this.warn3C_airTempMaxF,
    required this.warn3C_windMinMph,
    required this.imminent4A_airTempMaxF,
    required this.imminent4A_minGrowthStage,
    required this.imminent4B_airTempMaxF,
    required this.imminent4B_dewSpreadMaxF,
    required this.imminent4B_windMaxMph,
    required this.nightLightMaxLux,
    required this.frostSensitiveFromStage,
    required this.notifyUserIds,
    this.updatedAt,
    this.updatedBy,
  });

  final bool enabled;
  final String growthStage;
  final String cultivar;
  final double criticalTempF;
  final int minExposureDurationMinutes;
  final double eventMarginF;
  final double allClearMarginF;
  final int allClearStableMinutes;
  final int allClearForecastWindowHours;
  final int allClearHoldMinutes;
  final int warningMinConsecutiveReadings;

  final double windCalmMaxMph;
  final double windLightMaxMph;
  final double windModerateMaxMph;
  final double leafWetnessDryMaxPercent;
  final double leafWetnessWetMinPercent;

  // ignore_for_file: non_constant_identifier_names — field names deliberately
  // mirror the frostRuleConfig keys read by the Cloud Functions engine.
  final double watch2A_airTempMaxF;
  final double watch2A_coolingRateMinFPerHr;
  final double watch2A_windMaxMph;
  final double watch2A_dewSpreadMinF;
  final int watch2B_forecastHorizonHours;
  final double watch2B_referenceThresholdF;

  final double warn3A_airTempMaxF;
  final double warn3A_windMaxMph;
  final double warn3A_coolingRateMinFPerHr;
  final double warn3A_dewSpreadMaxF;
  final double warn3B_airTempMaxF;
  final double warn3B_windMaxMph;
  final double warn3B_coolingRateMinFPerHr;
  final double warn3B_dewSpreadMinF;
  final double warn3B_projected2hMaxF;
  final double warn3C_airTempMaxF;
  final double warn3C_windMinMph;

  final double imminent4A_airTempMaxF;
  final String imminent4A_minGrowthStage;
  final double imminent4B_airTempMaxF;
  final double imminent4B_dewSpreadMaxF;
  final double imminent4B_windMaxMph;

  final int nightLightMaxLux;
  final String frostSensitiveFromStage;

  final List<String> notifyUserIds;
  final DateTime? updatedAt;
  final String? updatedBy;

  static const Map<String, Object> _defaults = {
    'enabled': false,
    'growthStage': 'dormant',
    'cultivar': '',
    'criticalTempF': 32.0,
    'minExposureDurationMinutes': 30,
    'eventMarginF': 2.0,
    'allClearMarginF': 2.0,
    'allClearStableMinutes': 30,
    'allClearForecastWindowHours': 1,
    'allClearHoldMinutes': 60,
    'warningMinConsecutiveReadings': 2,
    'windCalmMaxMph': 2.0,
    'windLightMaxMph': 5.0,
    'windModerateMaxMph': 10.0,
    'leafWetnessDryMaxPercent': 20.0,
    'leafWetnessWetMinPercent': 30.0,
    'watch2A_airTempMaxF': 42.0,
    'watch2A_coolingRateMinFPerHr': -2.0,
    'watch2A_windMaxMph': 5.0,
    'watch2A_dewSpreadMinF': 5.0,
    'watch2B_forecastHorizonHours': 6,
    'watch2B_referenceThresholdF': 37.0,
    'warn3A_airTempMaxF': 36.0,
    'warn3A_windMaxMph': 3.0,
    'warn3A_coolingRateMinFPerHr': -1.0,
    'warn3A_dewSpreadMaxF': 4.0,
    'warn3B_airTempMaxF': 37.0,
    'warn3B_windMaxMph': 5.0,
    'warn3B_coolingRateMinFPerHr': -2.0,
    'warn3B_dewSpreadMinF': 4.0,
    'warn3B_projected2hMaxF': 32.0,
    'warn3C_airTempMaxF': 36.0,
    'warn3C_windMinMph': 5.0,
    'imminent4A_airTempMaxF': 33.0,
    'imminent4A_minGrowthStage': 'budBreak',
    'imminent4B_airTempMaxF': 33.0,
    'imminent4B_dewSpreadMaxF': 1.0,
    'imminent4B_windMaxMph': 3.0,
    'nightLightMaxLux': 5000,
    'frostSensitiveFromStage': 'swollenBud',
  };

  /// Spec-faithful defaults, used both as the starting point for a
  /// zone that has never had `frostRuleConfig` set, and as the fallback
  /// for any individual field missing from a partially-set doc.
  factory FrostRuleConfig.defaults() => FrostRuleConfig.fromMap(null);

  factory FrostRuleConfig.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const {};

    String stringOr(String key) {
      final value = map[key];
      if (value is String && value.isNotEmpty) return value;
      return _defaults[key] as String;
    }

    double doubleOr(String key) {
      return _doubleFromValue(map[key]) ?? (_defaults[key] as num).toDouble();
    }

    int intOr(String key) {
      return _intFromValue(map[key]) ?? (_defaults[key] as num).toInt();
    }

    return FrostRuleConfig(
      enabled: map['enabled'] == true,
      growthStage: stringOr('growthStage'),
      cultivar: map['cultivar'] is String ? map['cultivar'] as String : '',
      criticalTempF: doubleOr('criticalTempF'),
      minExposureDurationMinutes: intOr('minExposureDurationMinutes'),
      eventMarginF: doubleOr('eventMarginF'),
      allClearMarginF: doubleOr('allClearMarginF'),
      allClearStableMinutes: intOr('allClearStableMinutes'),
      allClearForecastWindowHours: intOr('allClearForecastWindowHours'),
      allClearHoldMinutes: intOr('allClearHoldMinutes'),
      warningMinConsecutiveReadings: intOr('warningMinConsecutiveReadings'),
      windCalmMaxMph: doubleOr('windCalmMaxMph'),
      windLightMaxMph: doubleOr('windLightMaxMph'),
      windModerateMaxMph: doubleOr('windModerateMaxMph'),
      leafWetnessDryMaxPercent: doubleOr('leafWetnessDryMaxPercent'),
      leafWetnessWetMinPercent: doubleOr('leafWetnessWetMinPercent'),
      watch2A_airTempMaxF: doubleOr('watch2A_airTempMaxF'),
      watch2A_coolingRateMinFPerHr: doubleOr('watch2A_coolingRateMinFPerHr'),
      watch2A_windMaxMph: doubleOr('watch2A_windMaxMph'),
      watch2A_dewSpreadMinF: doubleOr('watch2A_dewSpreadMinF'),
      watch2B_forecastHorizonHours: intOr('watch2B_forecastHorizonHours'),
      watch2B_referenceThresholdF: doubleOr('watch2B_referenceThresholdF'),
      warn3A_airTempMaxF: doubleOr('warn3A_airTempMaxF'),
      warn3A_windMaxMph: doubleOr('warn3A_windMaxMph'),
      warn3A_coolingRateMinFPerHr: doubleOr('warn3A_coolingRateMinFPerHr'),
      warn3A_dewSpreadMaxF: doubleOr('warn3A_dewSpreadMaxF'),
      warn3B_airTempMaxF: doubleOr('warn3B_airTempMaxF'),
      warn3B_windMaxMph: doubleOr('warn3B_windMaxMph'),
      warn3B_coolingRateMinFPerHr: doubleOr('warn3B_coolingRateMinFPerHr'),
      warn3B_dewSpreadMinF: doubleOr('warn3B_dewSpreadMinF'),
      warn3B_projected2hMaxF: doubleOr('warn3B_projected2hMaxF'),
      warn3C_airTempMaxF: doubleOr('warn3C_airTempMaxF'),
      warn3C_windMinMph: doubleOr('warn3C_windMinMph'),
      imminent4A_airTempMaxF: doubleOr('imminent4A_airTempMaxF'),
      imminent4A_minGrowthStage: stringOr('imminent4A_minGrowthStage'),
      imminent4B_airTempMaxF: doubleOr('imminent4B_airTempMaxF'),
      imminent4B_dewSpreadMaxF: doubleOr('imminent4B_dewSpreadMaxF'),
      imminent4B_windMaxMph: doubleOr('imminent4B_windMaxMph'),
      nightLightMaxLux: intOr('nightLightMaxLux'),
      frostSensitiveFromStage: stringOr('frostSensitiveFromStage'),
      notifyUserIds: map['notifyUserIds'] is List
          ? List<String>.from((map['notifyUserIds'] as List).map((e) => e.toString()))
          : const [],
      updatedAt: _dateFromValue(map['updatedAt']),
      updatedBy: map['updatedBy'] is String ? map['updatedBy'] as String : null,
    );
  }

  /// Every threshold field keyed by its `frostRuleConfig` field name, for
  /// driving the generated config form and for diffing old-vs-new values
  /// when writing the `frostConfigAudit` trail. Excludes `notifyUserIds`,
  /// `updatedAt`, `updatedBy` (not user-editable threshold fields).
  Map<String, dynamic> toFieldMap() {
    return {
      'enabled': enabled,
      'growthStage': growthStage,
      'cultivar': cultivar,
      'criticalTempF': criticalTempF,
      'minExposureDurationMinutes': minExposureDurationMinutes,
      'eventMarginF': eventMarginF,
      'allClearMarginF': allClearMarginF,
      'allClearStableMinutes': allClearStableMinutes,
      'allClearForecastWindowHours': allClearForecastWindowHours,
      'allClearHoldMinutes': allClearHoldMinutes,
      'warningMinConsecutiveReadings': warningMinConsecutiveReadings,
      'windCalmMaxMph': windCalmMaxMph,
      'windLightMaxMph': windLightMaxMph,
      'windModerateMaxMph': windModerateMaxMph,
      'leafWetnessDryMaxPercent': leafWetnessDryMaxPercent,
      'leafWetnessWetMinPercent': leafWetnessWetMinPercent,
      'watch2A_airTempMaxF': watch2A_airTempMaxF,
      'watch2A_coolingRateMinFPerHr': watch2A_coolingRateMinFPerHr,
      'watch2A_windMaxMph': watch2A_windMaxMph,
      'watch2A_dewSpreadMinF': watch2A_dewSpreadMinF,
      'watch2B_forecastHorizonHours': watch2B_forecastHorizonHours,
      'watch2B_referenceThresholdF': watch2B_referenceThresholdF,
      'warn3A_airTempMaxF': warn3A_airTempMaxF,
      'warn3A_windMaxMph': warn3A_windMaxMph,
      'warn3A_coolingRateMinFPerHr': warn3A_coolingRateMinFPerHr,
      'warn3A_dewSpreadMaxF': warn3A_dewSpreadMaxF,
      'warn3B_airTempMaxF': warn3B_airTempMaxF,
      'warn3B_windMaxMph': warn3B_windMaxMph,
      'warn3B_coolingRateMinFPerHr': warn3B_coolingRateMinFPerHr,
      'warn3B_dewSpreadMinF': warn3B_dewSpreadMinF,
      'warn3B_projected2hMaxF': warn3B_projected2hMaxF,
      'warn3C_airTempMaxF': warn3C_airTempMaxF,
      'warn3C_windMinMph': warn3C_windMinMph,
      'imminent4A_airTempMaxF': imminent4A_airTempMaxF,
      'imminent4A_minGrowthStage': imminent4A_minGrowthStage,
      'imminent4B_airTempMaxF': imminent4B_airTempMaxF,
      'imminent4B_dewSpreadMaxF': imminent4B_dewSpreadMaxF,
      'imminent4B_windMaxMph': imminent4B_windMaxMph,
      'nightLightMaxLux': nightLightMaxLux,
      'frostSensitiveFromStage': frostSensitiveFromStage,
    };
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      ...toFieldMap(),
      'notifyUserIds': notifyUserIds,
    };
  }

  static double? _doubleFromValue(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _intFromValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _dateFromValue(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
