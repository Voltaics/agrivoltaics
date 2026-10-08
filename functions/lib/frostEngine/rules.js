/**
 * Pure rule evaluation for the frost alert engine's six alert levels.
 *
 * Every function here takes already-computed values (derived sensor math
 * from derivations.js, farmer config, and already-tracked persistence/event
 * state) and returns plain booleans/objects - no Firestore/BigQuery/network
 * access. `evaluateFrostLevel` is the single entrypoint a later orchestrator
 * (evaluateZoneFrostEngine.js) will call once per ingest tick.
 */

const {defaultIfNull, isGrowthStageAtLeast} = require('./utils');

const ALERT_LEVEL = {
  NORMAL: 'normal',
  WATCH: 'watch',
  WARNING: 'warning',
  IMMINENT: 'imminent',
  EVENT: 'event',
  ALL_CLEAR: 'allClear',
};

// Rank for the "never downgrade because of stale/missing data" rule.
// ALL_CLEAR is a recovery state reached only via an explicit All-Clear check
// (see evaluateFrostLevel's recovery gating below), not part of this
// monotonic ladder.
const LEVEL_RANK = {
  [ALERT_LEVEL.NORMAL]: 0,
  [ALERT_LEVEL.WATCH]: 1,
  [ALERT_LEVEL.WARNING]: 2,
  [ALERT_LEVEL.IMMINENT]: 3,
  [ALERT_LEVEL.EVENT]: 4,
};

const WARNING_SUBTYPE = {
  RADIATION: 'radiation',
  ADVECTIVE: 'advective',
  MIXED: 'mixed',
};

/**
 * Advances a single rule's "how many consecutive readings has this held
 * true" streak. This is the generic persistence primitive every "persist for
 * N readings" rule in the spec is built on, instead of a bespoke counter per
 * rule.
 *
 * @param {{consecutiveTrue: number, lastTrueAt: (string|null)}|null|undefined} prevStreak
 * @param {boolean} conditionTrueThisTick
 * @param {string} nowIso
 * @return {{consecutiveTrue: number, lastTrueAt: (string|null), lastEvalAt: string}}
 */
function updateStreak(prevStreak, conditionTrueThisTick, nowIso) {
  const prevCount = prevStreak && typeof prevStreak.consecutiveTrue === 'number' ?
    prevStreak.consecutiveTrue : 0;
  const prevLastTrueAt = prevStreak ? defaultIfNull(prevStreak.lastTrueAt, null) : null;

  return {
    consecutiveTrue: conditionTrueThisTick ? prevCount + 1 : 0,
    lastTrueAt: conditionTrueThisTick ? nowIso : prevLastTrueAt,
    lastEvalAt: nowIso,
  };
}

/**
 * Rule 2A: rapid dry-air cooling (Frost Watch).
 * @param {Object} derived
 * @param {Object} config
 * @return {boolean}
 */
function checkRule2A(derived, config) {
  if (derived.airTempF === null || derived.coolingRate60FPerHr === null ||
      derived.windSpeedMph === null || derived.dewPointSpreadF === null) {
    return false;
  }
  return derived.airTempF <= defaultIfNull(config.watch2A_airTempMaxF, 42) &&
    derived.coolingRate60FPerHr <= defaultIfNull(config.watch2A_coolingRateMinFPerHr, -2) &&
    derived.windSpeedMph < defaultIfNull(config.watch2A_windMaxMph, 5) &&
    derived.dewPointSpreadF > defaultIfNull(config.watch2A_dewSpreadMinF, 5);
}

/**
 * Rule 2B: forecast/projected temperature approaching the Warning threshold
 * within the configured horizon. Omitted (returns false) when no forecast is
 * available, per the spec's own "check for availability... to omit when
 * unavailable" guidance - it does not fail the whole Watch level, it just
 * doesn't contribute this sub-condition.
 *
 * @param {{minTempNextNHoursF: (number|null)}|null} forecast
 * @param {Object} config
 * @return {boolean}
 */
function checkRule2B(forecast, config) {
  if (!forecast || forecast.minTempNextNHoursF === null || forecast.minTempNextNHoursF === undefined) {
    return false;
  }
  const referenceThresholdF = defaultIfNull(config.watch2B_referenceThresholdF, 37);
  return forecast.minTempNextNHoursF <= referenceThresholdF;
}

/**
 * Rule 3A: classic radiation-frost pattern.
 * @param {Object} derived
 * @param {Object} config
 * @return {boolean}
 */
function checkRule3A(derived, config) {
  if (derived.airTempF === null || derived.windSpeedMph === null ||
      derived.coolingRate60FPerHr === null) {
    return false;
  }
  const dewCondition = derived.dewPointSpreadF !== null &&
    derived.dewPointSpreadF <= defaultIfNull(config.warn3A_dewSpreadMaxF, 4);
  const wetnessCondition = !!(derived.leafWetness && derived.leafWetness.justTransitionedDryToWet === true);

  return derived.airTempF <= defaultIfNull(config.warn3A_airTempMaxF, 36) &&
    derived.windSpeedMph <= defaultIfNull(config.warn3A_windMaxMph, 3) &&
    derived.coolingRate60FPerHr <= defaultIfNull(config.warn3A_coolingRateMinFPerHr, -1) &&
    derived.isNightOrLowLight === true &&
    (dewCondition || wetnessCondition);
}

/**
 * Rule 3B: rapid dry-air cooling projected to reach 32F within two hours.
 * @param {Object} derived
 * @param {Object} config
 * @return {boolean}
 */
function checkRule3B(derived, config) {
  if (derived.airTempF === null || derived.windSpeedMph === null ||
      derived.coolingRate60FPerHr === null || derived.dewPointSpreadF === null ||
      derived.projectedTemp2hF === null) {
    return false;
  }
  return derived.airTempF <= defaultIfNull(config.warn3B_airTempMaxF, 37) &&
    derived.windSpeedMph <= defaultIfNull(config.warn3B_windMaxMph, 5) &&
    derived.coolingRate60FPerHr <= defaultIfNull(config.warn3B_coolingRateMinFPerHr, -2) &&
    derived.dewPointSpreadF > defaultIfNull(config.warn3B_dewSpreadMinF, 4) &&
    derived.projectedTemp2hF <= defaultIfNull(config.warn3B_projected2hMaxF, 32);
}

/**
 * Rule 3C: wind-driven freeze approaching (feeds Advective Freeze Warning).
 * @param {Object} derived
 * @param {{regionalFreezingAirIncoming: boolean}|null} forecast
 * @param {Object} config
 * @return {boolean}
 */
function checkRule3C(derived, forecast, config) {
  if (derived.airTempF === null || derived.windSpeedMph === null ||
      derived.coolingRate60FPerHr === null) {
    return false;
  }
  const tempFalling = derived.coolingRate60FPerHr < 0;
  const forecastFreezingAir = !!(forecast && forecast.regionalFreezingAirIncoming === true);

  return derived.airTempF <= defaultIfNull(config.warn3C_airTempMaxF, 36) &&
    derived.windSpeedMph > defaultIfNull(config.warn3C_windMinMph, 5) &&
    tempFalling &&
    forecastFreezingAir;
}

/**
 * Rule 4A: critical air-temperature approach.
 * @param {Object} derived
 * @param {number|null} budZoneTempF
 * @param {string} growthStage
 * @param {Object} config
 * @return {boolean}
 */
function checkRule4A(derived, budZoneTempF, growthStage, config) {
  if (derived.airTempF === null || derived.coolingRate60FPerHr === null) return false;
  const minStage = defaultIfNull(config.imminent4A_minGrowthStage, 'budBreak');
  return derived.airTempF <= defaultIfNull(config.imminent4A_airTempMaxF, 33) &&
    derived.coolingRate60FPerHr < 0 &&
    isGrowthStageAtLeast(growthStage, minStage);
}

/**
 * Rule 4B: frost forming on wet tissue. Per spec this combines four
 * "approaching" bullets (air temp, wetness, dew spread, wind) with a
 * separate "Trigger if Tbud_zone <= 32F" line; interpreted here as: all four
 * ambient bullets plus the bud-zone temperature actually reaching the
 * farmer's configured critical threshold - using `config.criticalTempF`
 * rather than a hardcoded 32F, consistent with Rule 4C using the same
 * farmer-configurable value.
 *
 * @param {Object} derived
 * @param {number|null} budZoneTempF
 * @param {Object} config
 * @return {boolean}
 */
function checkRule4B(derived, budZoneTempF, config) {
  if (budZoneTempF === null || derived.airTempF === null ||
      derived.dewPointSpreadF === null || derived.windSpeedMph === null) {
    return false;
  }
  const leafActive = !!(derived.leafWetness && derived.leafWetness.state === 'wet');
  return leafActive &&
    derived.airTempF <= defaultIfNull(config.imminent4B_airTempMaxF, 33) &&
    budZoneTempF <= defaultIfNull(config.criticalTempF, 32) &&
    derived.dewPointSpreadF <= defaultIfNull(config.imminent4B_dewSpreadMaxF, 1) &&
    derived.windSpeedMph <= defaultIfNull(config.imminent4B_windMaxMph, 3);
}

/**
 * Rule 4C: bud-zone temperature reaches the configured critical threshold.
 * @param {number|null} budZoneTempF
 * @param {Object} config
 * @return {boolean}
 */
function checkRule4C(budZoneTempF, config) {
  if (budZoneTempF === null) return false;
  return budZoneTempF <= defaultIfNull(config.criticalTempF, 32);
}

/**
 * Level 5: Freeze Event in Progress. Either sustained exposure at/below the
 * critical threshold for the configured minimum duration, or a single-reading
 * drop of at least the configured margin below critical.
 *
 * @param {number|null} budZoneTempF
 * @param {Object} config
 * @param {{timeBelowCriticalMinutes: number}} eventAccumulators - already
 *   tracked by the caller (a later phase's stateStore.js); this function
 *   does not compute durations itself.
 * @return {boolean}
 */
function checkLevel5(budZoneTempF, config, eventAccumulators) {
  const criticalTempF = defaultIfNull(config.criticalTempF, 32);
  const minExposure = defaultIfNull(config.minExposureDurationMinutes, 30);
  const margin = defaultIfNull(config.eventMarginF, 2);

  const sustainedExposure = !!(eventAccumulators &&
    typeof eventAccumulators.timeBelowCriticalMinutes === 'number' &&
    eventAccumulators.timeBelowCriticalMinutes >= minExposure);

  const singleReadingDrop = budZoneTempF !== null &&
    (criticalTempF - budZoneTempF) >= margin;

  return sustainedExposure || singleReadingDrop;
}

/**
 * Level 6: All Clear. Requires the recovery duration to already be tracked
 * by the caller (`recoveryStableMinutes`) - this function only applies the
 * spec's three-part gate, it doesn't measure stability itself.
 *
 * @param {number|null} budZoneTempF
 * @param {Object} config
 * @param {{recoveryStableMinutes: number}} eventAccumulators
 * @param {{minTempNextNHoursF: (number|null)}|null} forecast
 * @return {boolean}
 */
function checkLevel6AllClear(budZoneTempF, config, eventAccumulators, forecast) {
  if (budZoneTempF === null) return false;

  const criticalTempF = defaultIfNull(config.criticalTempF, 32);
  const allClearMargin = defaultIfNull(config.allClearMarginF, 2);
  const stableMinutesNeeded = defaultIfNull(config.allClearStableMinutes, 30);

  const tempHighEnough = budZoneTempF >= criticalTempF + allClearMargin;
  const stableLongEnough = !!(eventAccumulators &&
    typeof eventAccumulators.recoveryStableMinutes === 'number' &&
    eventAccumulators.recoveryStableMinutes >= stableMinutesNeeded);

  // "No forecasted decline below critical threshold expected during the next
  // hour" - omitted (treated as satisfied) when no forecast is available,
  // per the same "omit when unavailable" principle used by rules 2B/3C.
  const noForecastedDecline = !forecast || forecast.minTempNextNHoursF === null ||
    forecast.minTempNextNHoursF === undefined ||
    forecast.minTempNextNHoursF >= criticalTempF;

  return tempHighEnough && stableLongEnough && noForecastedDecline;
}

/**
 * Single entrypoint: given fully-formed derived values, config, persistence
 * state and event accumulators, decides the zone's alert level for this
 * evaluation tick.
 *
 * @param {Object} input
 * @param {Object} input.derived - Assembled by the caller from derivations.js
 *   functions: {airTempF, dewPointF, dewPointSpreadF, coolingRate60FPerHr,
 *   projectedTemp2hF, windSpeedMph, isNightOrLowLight, leafWetness}.
 * @param {number|null} input.budZoneTempF - Bud-zone temperature. Phase 1:
 *   the zone's primary temperature reading (no dedicated bud-zone sensor
 *   yet - see plan §4 assumption).
 * @param {string} input.growthStage
 * @param {{minTempNextNHoursF: (number|null), regionalFreezingAirIncoming: boolean}|null} input.forecast
 * @param {Object} input.config - frostRuleConfig; every threshold read here
 *   falls back to the spec's default if not set.
 * @param {Object} input.streaksInput - Previous tick's {rule3A, rule3B, rule3C} streaks.
 * @param {Object} input.eventAccumulators - {timeBelowCriticalMinutes, recoveryStableMinutes}.
 * @param {string} input.prevLevel - Previous alert level.
 * @param {boolean} input.dataQualityOk - False if required sensors are stale/missing this tick.
 * @param {string} input.nowIso
 * @param {number|null} [input.minutesInCurrentLevel] - Minutes since prevLevel
 *   was entered (state.levelEnteredAt); only consulted when prevLevel is
 *   'allClear', to decide whether the hold period has elapsed.
 * @return {{level: string, subType: (string|null), matchedRuleIds: string[], streaks: Object}}
 */
function evaluateFrostLevel(input) {
  const {
    derived, budZoneTempF, growthStage, forecast, config,
    streaksInput, eventAccumulators, prevLevel, dataQualityOk, nowIso,
    minutesInCurrentLevel,
  } = input;

  const rule2A = checkRule2A(derived, config);
  const rule2B = checkRule2B(forecast, config);

  const rule3ARaw = checkRule3A(derived, config);
  const rule3BRaw = checkRule3B(derived, config);
  const rule3CRaw = checkRule3C(derived, forecast, config);

  const streaks = {
    rule3A: updateStreak(streaksInput ? streaksInput.rule3A : null, rule3ARaw, nowIso),
    rule3B: updateStreak(streaksInput ? streaksInput.rule3B : null, rule3BRaw, nowIso),
    rule3C: updateStreak(streaksInput ? streaksInput.rule3C : null, rule3CRaw, nowIso),
  };

  const persistReadings = defaultIfNull(config.warningMinConsecutiveReadings, 2);
  const rule3AFires = streaks.rule3A.consecutiveTrue >= persistReadings;
  const rule3BFires = streaks.rule3B.consecutiveTrue >= persistReadings;
  const rule3CFires = streaks.rule3C.consecutiveTrue >= persistReadings;

  const frostSensitiveThreshold = defaultIfNull(config.frostSensitiveFromStage, 'swollenBud');
  const frostSensitiveTissue = isGrowthStageAtLeast(growthStage, frostSensitiveThreshold);

  const watchTriggered = frostSensitiveTissue && (rule2A || rule2B);
  const radiationWarning = frostSensitiveTissue && (rule3AFires || rule3BFires);
  const advectiveWarning = frostSensitiveTissue && rule3CFires;

  const rule4A = checkRule4A(derived, budZoneTempF, growthStage, config);
  const rule4B = checkRule4B(derived, budZoneTempF, config);
  const rule4C = checkRule4C(budZoneTempF, config);

  const level5 = checkLevel5(budZoneTempF, config, eventAccumulators);
  const allClearReady = checkLevel6AllClear(budZoneTempF, config, eventAccumulators, forecast);

  let level = ALERT_LEVEL.NORMAL;
  let subType = null;
  const matchedRuleIds = [];

  if (level5) {
    level = ALERT_LEVEL.EVENT;
    matchedRuleIds.push('level5');
  } else if (rule4A || rule4B || rule4C) {
    level = ALERT_LEVEL.IMMINENT;
    if (rule4A) matchedRuleIds.push('rule4A');
    if (rule4B) matchedRuleIds.push('rule4B');
    if (rule4C) matchedRuleIds.push('rule4C');
  } else if (radiationWarning || advectiveWarning) {
    level = ALERT_LEVEL.WARNING;
    if (radiationWarning) {
      subType = WARNING_SUBTYPE.RADIATION;
      if (rule3AFires) matchedRuleIds.push('rule3A');
      if (rule3BFires) matchedRuleIds.push('rule3B');
    }
    if (advectiveWarning) {
      // Under default thresholds, 3A/3B (wind <=3 or <=5 mph) and 3C
      // (wind > 5 mph) are mutually exclusive, so MIXED can't fire with
      // defaults - it becomes reachable if a farmer's configured wind
      // thresholds overlap (e.g. a lower warn3C_windMinMph).
      subType = subType ? WARNING_SUBTYPE.MIXED : WARNING_SUBTYPE.ADVECTIVE;
      matchedRuleIds.push('rule3C');
    }
  } else if (watchTriggered) {
    level = ALERT_LEVEL.WATCH;
    if (rule2A) matchedRuleIds.push('rule2A');
    if (rule2B) matchedRuleIds.push('rule2B');
  }

  // Recovery gating: once at Imminent/Event/AllClear, only move back down via
  // an explicit All-Clear pass - never silently fall to a lower computed
  // level just because this tick's raw conditions look better. This is an
  // interpretation of the spec's "do not lower an alert level until [...]"
  // language (stated under Level 6) applied to the imminent/event/all-clear
  // band specifically - flagged in the plan as an assumption to confirm with
  // the professor. If raw conditions are already escalating again (rank at
  // or above prevLevel, e.g. Imminent -> Event), that fresh escalation is
  // let through unchanged rather than being trapped by this gate.
  const recoveryBand = prevLevel === ALERT_LEVEL.IMMINENT ||
    prevLevel === ALERT_LEVEL.EVENT || prevLevel === ALERT_LEVEL.ALL_CLEAR;

  if (recoveryBand) {
    if (prevLevel === ALERT_LEVEL.ALL_CLEAR) {
      if (level === ALERT_LEVEL.NORMAL) {
        // Already past the All-Clear gate once - hold there until the
        // configured hold period has elapsed, then fully clear to Normal.
        // The spec doesn't say whether All Clear auto-reverts or needs
        // acknowledgment; this is the assumed default (see plan §1c).
        const holdMinutes = defaultIfNull(config.allClearHoldMinutes, 60);
        const heldLongEnough = typeof minutesInCurrentLevel === 'number' &&
          minutesInCurrentLevel >= holdMinutes;
        level = heldLongEnough ? ALERT_LEVEL.NORMAL : ALERT_LEVEL.ALL_CLEAR;
      }
      // else: a fresh Watch/Warning/Imminent/Event escalation during the
      // hold window - let it through unchanged rather than trapping it here.
    } else {
      // prevLevel was Imminent or Event - only drop via an explicit
      // All-Clear pass. Gate on *rank*, not just "computed level is Normal",
      // so a partial recovery that still satisfies a lower level (e.g.
      // Imminent's rules stop firing but a Warning rule still does) is also
      // held at prevLevel instead of silently skipping the All-Clear check.
      const prevBandRank = LEVEL_RANK[prevLevel];
      const rawLevelRank = LEVEL_RANK[level];
      const droppedBelowPrevLevel = typeof rawLevelRank === 'number' &&
        rawLevelRank < prevBandRank;
      if (droppedBelowPrevLevel) {
        level = allClearReady ? ALERT_LEVEL.ALL_CLEAR : prevLevel;
        if (allClearReady) matchedRuleIds.push('level6AllClear');
      }
    }
  }

  // Never downgrade because of stale/missing data (spec "minimum rules").
  const prevRank = LEVEL_RANK[prevLevel];
  const levelRank = LEVEL_RANK[level];
  if (dataQualityOk === false && typeof prevRank === 'number' && typeof levelRank === 'number' &&
      levelRank < prevRank) {
    level = prevLevel;
  }

  return {level, subType, matchedRuleIds, streaks};
}

module.exports = {
  ALERT_LEVEL,
  LEVEL_RANK,
  WARNING_SUBTYPE,
  updateStreak,
  checkRule2A,
  checkRule2B,
  checkRule3A,
  checkRule3B,
  checkRule3C,
  checkRule4A,
  checkRule4B,
  checkRule4C,
  checkLevel5,
  checkLevel6AllClear,
  evaluateFrostLevel,
};
