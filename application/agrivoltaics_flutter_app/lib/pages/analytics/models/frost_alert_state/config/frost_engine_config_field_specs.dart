import '../../../../../models/frost_rule_config.dart';

/// Widget shape a [FrostConfigFieldSpec] should render as. Kept deliberately
/// small — every `frostRuleConfig` threshold is either a plain number, a
/// count/duration, free text, or a growth-stage pick.
enum FrostConfigFieldType {
  decimal,
  integer,
  text,
  growthStageDropdown,
}

/// Declarative description of one editable `frostRuleConfig` field, driving
/// the generated grouped form in `frost_engine_config_form_builder.dart`.
///
/// Deliberately not a hand-built controller per field (unlike
/// `create_alert_rule_dialog.dart`'s per-rule-type controllers) — this
/// config surface has ~35 fields, too many for that pattern to stay
/// readable.
class FrostConfigFieldSpec {
  const FrostConfigFieldSpec({
    required this.key,
    required this.label,
    required this.group,
    required this.type,
    this.unit,
    this.helperText,
    this.min,
    this.max,
  });

  /// Matches a `frostRuleConfig` key exactly (see `FrostRuleConfig.toFieldMap`).
  final String key;
  final String label;
  final String group;
  final FrostConfigFieldType type;
  final String? unit;
  final String? helperText;
  final num? min;
  final num? max;
}

const String frostConfigGroupGeneral = 'General';
const String frostConfigGroupAllClear = 'Recovery / All Clear';
const String frostConfigGroupWindLeaf = 'Wind & Leaf Wetness';
const String frostConfigGroupWatch = 'Watch (Level 2)';
const String frostConfigGroupWarning = 'Warning (Level 3)';
const String frostConfigGroupImminent = 'Imminent (Level 4)';

/// Group display order for the form builder.
const List<String> frostConfigGroupOrder = [
  frostConfigGroupGeneral,
  frostConfigGroupAllClear,
  frostConfigGroupWindLeaf,
  frostConfigGroupWatch,
  frostConfigGroupWarning,
  frostConfigGroupImminent,
];

/// Full declarative field list — one entry per user-editable `frostRuleConfig`
/// threshold. `enabled`, `cultivar`, and `notifyUserIds` are handled outside
/// this generic list by the dialog (a toggle, free-text field, and org-member
/// picker respectively don't need a grouped/collapsible section).
const List<FrostConfigFieldSpec> frostConfigFieldSpecs = [
  // General
  FrostConfigFieldSpec(
    key: 'growthStage',
    label: 'Current growth stage',
    group: frostConfigGroupGeneral,
    type: FrostConfigFieldType.growthStageDropdown,
  ),
  FrostConfigFieldSpec(
    key: 'criticalTempF',
    label: 'Critical temperature',
    group: frostConfigGroupGeneral,
    type: FrostConfigFieldType.decimal,
    unit: '°F',
    helperText: 'Bud-zone temperature that defines a freeze event for this growth stage.',
  ),
  FrostConfigFieldSpec(
    key: 'frostSensitiveFromStage',
    label: 'Frost-sensitive from stage',
    group: frostConfigGroupGeneral,
    type: FrostConfigFieldType.growthStageDropdown,
    helperText: 'Watch/Warning rules only fire once the vine has reached this stage.',
  ),
  FrostConfigFieldSpec(
    key: 'minExposureDurationMinutes',
    label: 'Minimum exposure duration',
    group: frostConfigGroupGeneral,
    type: FrostConfigFieldType.integer,
    unit: 'min',
    min: 0,
    helperText: 'Sustained time at/below critical temperature before Level 5 (Event) fires.',
  ),
  FrostConfigFieldSpec(
    key: 'eventMarginF',
    label: 'Event margin',
    group: frostConfigGroupGeneral,
    type: FrostConfigFieldType.decimal,
    unit: '°F',
    helperText: 'A single reading this far below critical also fires Level 5 immediately.',
  ),
  FrostConfigFieldSpec(
    key: 'warningMinConsecutiveReadings',
    label: 'Warning persistence',
    group: frostConfigGroupGeneral,
    type: FrostConfigFieldType.integer,
    unit: 'readings',
    min: 1,
    helperText: 'Consecutive readings a Warning-level condition must hold before it fires.',
  ),
  FrostConfigFieldSpec(
    key: 'nightLightMaxLux',
    label: 'Night / low-light threshold',
    group: frostConfigGroupGeneral,
    type: FrostConfigFieldType.integer,
    unit: 'lux',
    min: 0,
    helperText: 'Light readings at or below this are treated as night/low-light.',
  ),

  // Recovery / All Clear
  FrostConfigFieldSpec(
    key: 'allClearMarginF',
    label: 'All-Clear margin',
    group: frostConfigGroupAllClear,
    type: FrostConfigFieldType.decimal,
    unit: '°F',
    helperText: 'Bud-zone temperature must recover to critical + this margin.',
  ),
  FrostConfigFieldSpec(
    key: 'allClearStableMinutes',
    label: 'All-Clear stability window',
    group: frostConfigGroupAllClear,
    type: FrostConfigFieldType.integer,
    unit: 'min',
    min: 0,
    helperText: 'Minutes the recovery temperature must hold before All Clear is reached.',
  ),
  FrostConfigFieldSpec(
    key: 'allClearForecastWindowHours',
    label: 'All-Clear forecast window',
    group: frostConfigGroupAllClear,
    type: FrostConfigFieldType.integer,
    unit: 'hr',
    min: 0,
    helperText: 'No forecasted decline below critical within this window.',
  ),
  FrostConfigFieldSpec(
    key: 'allClearHoldMinutes',
    label: 'All-Clear hold before Normal',
    group: frostConfigGroupAllClear,
    type: FrostConfigFieldType.integer,
    unit: 'min',
    min: 0,
    helperText: 'How long to stay at All Clear before auto-reverting to Normal.',
  ),

  // Wind & Leaf Wetness
  FrostConfigFieldSpec(
    key: 'windCalmMaxMph',
    label: 'Calm wind ceiling',
    group: frostConfigGroupWindLeaf,
    type: FrostConfigFieldType.decimal,
    unit: 'mph',
    min: 0,
  ),
  FrostConfigFieldSpec(
    key: 'windLightMaxMph',
    label: 'Light wind ceiling',
    group: frostConfigGroupWindLeaf,
    type: FrostConfigFieldType.decimal,
    unit: 'mph',
    min: 0,
  ),
  FrostConfigFieldSpec(
    key: 'windModerateMaxMph',
    label: 'Moderate wind ceiling',
    group: frostConfigGroupWindLeaf,
    type: FrostConfigFieldType.decimal,
    unit: 'mph',
    min: 0,
    helperText: 'Above this, wind is classified Strong.',
  ),
  FrostConfigFieldSpec(
    key: 'leafWetnessDryMaxPercent',
    label: 'Leaf-wetness dry ceiling',
    group: frostConfigGroupWindLeaf,
    type: FrostConfigFieldType.decimal,
    unit: '%',
    min: 0,
    max: 100,
  ),
  FrostConfigFieldSpec(
    key: 'leafWetnessWetMinPercent',
    label: 'Leaf-wetness wet floor',
    group: frostConfigGroupWindLeaf,
    type: FrostConfigFieldType.decimal,
    unit: '%',
    min: 0,
    max: 100,
    helperText: 'Between the dry ceiling and wet floor, the previous state is retained (hysteresis).',
  ),

  // Watch (Level 2)
  FrostConfigFieldSpec(
    key: 'watch2A_airTempMaxF',
    label: 'Rule 2A: air temp ceiling',
    group: frostConfigGroupWatch,
    type: FrostConfigFieldType.decimal,
    unit: '°F',
  ),
  FrostConfigFieldSpec(
    key: 'watch2A_coolingRateMinFPerHr',
    label: 'Rule 2A: cooling rate ceiling',
    group: frostConfigGroupWatch,
    type: FrostConfigFieldType.decimal,
    unit: '°F/hr',
    helperText: 'Negative = falling. Condition fires at or below this rate.',
  ),
  FrostConfigFieldSpec(
    key: 'watch2A_windMaxMph',
    label: 'Rule 2A: wind ceiling',
    group: frostConfigGroupWatch,
    type: FrostConfigFieldType.decimal,
    unit: 'mph',
    min: 0,
  ),
  FrostConfigFieldSpec(
    key: 'watch2A_dewSpreadMinF',
    label: 'Rule 2A: dew-point spread floor',
    group: frostConfigGroupWatch,
    type: FrostConfigFieldType.decimal,
    unit: '°F',
  ),
  FrostConfigFieldSpec(
    key: 'watch2B_forecastHorizonHours',
    label: 'Rule 2B: forecast horizon',
    group: frostConfigGroupWatch,
    type: FrostConfigFieldType.integer,
    unit: 'hr',
    min: 0,
  ),
  FrostConfigFieldSpec(
    key: 'watch2B_referenceThresholdF',
    label: 'Rule 2B: forecast reference threshold',
    group: frostConfigGroupWatch,
    type: FrostConfigFieldType.decimal,
    unit: '°F',
    helperText: 'Watch fires if the forecast minimum within the horizon is at/below this.',
  ),

  // Warning (Level 3)
  FrostConfigFieldSpec(
    key: 'warn3A_airTempMaxF',
    label: 'Rule 3A (radiation): air temp ceiling',
    group: frostConfigGroupWarning,
    type: FrostConfigFieldType.decimal,
    unit: '°F',
  ),
  FrostConfigFieldSpec(
    key: 'warn3A_windMaxMph',
    label: 'Rule 3A (radiation): wind ceiling',
    group: frostConfigGroupWarning,
    type: FrostConfigFieldType.decimal,
    unit: 'mph',
    min: 0,
  ),
  FrostConfigFieldSpec(
    key: 'warn3A_coolingRateMinFPerHr',
    label: 'Rule 3A (radiation): cooling rate ceiling',
    group: frostConfigGroupWarning,
    type: FrostConfigFieldType.decimal,
    unit: '°F/hr',
  ),
  FrostConfigFieldSpec(
    key: 'warn3A_dewSpreadMaxF',
    label: 'Rule 3A (radiation): dew-point spread ceiling',
    group: frostConfigGroupWarning,
    type: FrostConfigFieldType.decimal,
    unit: '°F',
  ),
  FrostConfigFieldSpec(
    key: 'warn3B_airTempMaxF',
    label: 'Rule 3B (rapid cooling): air temp ceiling',
    group: frostConfigGroupWarning,
    type: FrostConfigFieldType.decimal,
    unit: '°F',
  ),
  FrostConfigFieldSpec(
    key: 'warn3B_windMaxMph',
    label: 'Rule 3B (rapid cooling): wind ceiling',
    group: frostConfigGroupWarning,
    type: FrostConfigFieldType.decimal,
    unit: 'mph',
    min: 0,
  ),
  FrostConfigFieldSpec(
    key: 'warn3B_coolingRateMinFPerHr',
    label: 'Rule 3B (rapid cooling): cooling rate ceiling',
    group: frostConfigGroupWarning,
    type: FrostConfigFieldType.decimal,
    unit: '°F/hr',
  ),
  FrostConfigFieldSpec(
    key: 'warn3B_dewSpreadMinF',
    label: 'Rule 3B (rapid cooling): dew-point spread floor',
    group: frostConfigGroupWarning,
    type: FrostConfigFieldType.decimal,
    unit: '°F',
  ),
  FrostConfigFieldSpec(
    key: 'warn3B_projected2hMaxF',
    label: 'Rule 3B (rapid cooling): 2-hour projected temp ceiling',
    group: frostConfigGroupWarning,
    type: FrostConfigFieldType.decimal,
    unit: '°F',
  ),
  FrostConfigFieldSpec(
    key: 'warn3C_airTempMaxF',
    label: 'Rule 3C (advective): air temp ceiling',
    group: frostConfigGroupWarning,
    type: FrostConfigFieldType.decimal,
    unit: '°F',
  ),
  FrostConfigFieldSpec(
    key: 'warn3C_windMinMph',
    label: 'Rule 3C (advective): wind floor',
    group: frostConfigGroupWarning,
    type: FrostConfigFieldType.decimal,
    unit: 'mph',
    min: 0,
    helperText: 'Condition fires above this wind speed, combined with falling temp + forecasted cold air.',
  ),

  // Imminent (Level 4)
  FrostConfigFieldSpec(
    key: 'imminent4A_airTempMaxF',
    label: 'Rule 4A: air temp ceiling',
    group: frostConfigGroupImminent,
    type: FrostConfigFieldType.decimal,
    unit: '°F',
  ),
  FrostConfigFieldSpec(
    key: 'imminent4A_minGrowthStage',
    label: 'Rule 4A: minimum growth stage',
    group: frostConfigGroupImminent,
    type: FrostConfigFieldType.growthStageDropdown,
  ),
  FrostConfigFieldSpec(
    key: 'imminent4B_airTempMaxF',
    label: 'Rule 4B: air temp ceiling',
    group: frostConfigGroupImminent,
    type: FrostConfigFieldType.decimal,
    unit: '°F',
    helperText: 'Reserved for a future ambient pre-check; Rule 4B currently gates on bud-zone temp only.',
  ),
  FrostConfigFieldSpec(
    key: 'imminent4B_dewSpreadMaxF',
    label: 'Rule 4B: dew-point spread ceiling',
    group: frostConfigGroupImminent,
    type: FrostConfigFieldType.decimal,
    unit: '°F',
  ),
  FrostConfigFieldSpec(
    key: 'imminent4B_windMaxMph',
    label: 'Rule 4B: wind ceiling',
    group: frostConfigGroupImminent,
    type: FrostConfigFieldType.decimal,
    unit: 'mph',
    min: 0,
  ),
];

/// Every field key in [frostConfigFieldSpecs], grouped in [frostConfigGroupOrder].
Map<String, List<FrostConfigFieldSpec>> frostConfigFieldsByGroup() {
  final result = <String, List<FrostConfigFieldSpec>>{
    for (final group in frostConfigGroupOrder) group: [],
  };
  for (final spec in frostConfigFieldSpecs) {
    result.putIfAbsent(spec.group, () => []).add(spec);
  }
  return result;
}

/// Sanity check (used by the widget test) that every generic field spec key
/// round-trips through [FrostRuleConfig.toFieldMap] — catches typos between
/// the two files at compile/test time rather than silently dropping a field.
bool frostConfigFieldSpecKeysMatchModel() {
  final modelKeys = FrostRuleConfig.defaults().toFieldMap().keys.toSet();
  final specKeys = frostConfigFieldSpecs.map((s) => s.key).toSet();
  const handledElsewhere = {'enabled', 'cultivar'};
  return specKeys.union(handledElsewhere).containsAll(modelKeys) &&
      modelKeys.containsAll(specKeys);
}
