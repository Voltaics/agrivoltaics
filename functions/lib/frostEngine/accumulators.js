/**
 * Stateful tick-to-tick bookkeeping for the frost engine: elapsed time,
 * event/recovery duration accumulators, per-field data-quality/staleness,
 * and continuous leaf-wetness duration.
 *
 * Every function here is pure - it takes the previous tick's tracked state
 * plus this tick's raw values and returns the next tracked state. The
 * caller (evaluateZoneFrostEngine.js) owns reading the previous state from
 * Firestore and persisting whatever these return; nothing in this file
 * touches Firestore/BigQuery.
 */

const {defaultIfNull} = require('./utils');

/**
 * @param {string|null} prevIso
 * @param {string} nowIso
 * @return {number|null} Minutes elapsed, or null if prevIso is missing/invalid
 *   or would imply negative elapsed time (clock skew) - callers should treat
 *   null as "unknown," not zero.
 */
function computeElapsedMinutes(prevIso, nowIso) {
  if (!prevIso) return null;
  const prevMs = Date.parse(prevIso);
  const nowMs = Date.parse(nowIso);
  if (!Number.isFinite(prevMs) || !Number.isFinite(nowMs) || nowMs < prevMs) return null;
  return (nowMs - prevMs) / 60000;
}

/**
 * Advances the "is this field stale" tracker for one field, per the spec's
 * minimum rules: mark stale after 2 missed reporting intervals during
 * Normal, after 1 missed interval at Watch or higher.
 *
 * @param {{stale: boolean, lastGoodAt: (string|null), missedIntervals: number}|null|undefined} prevFieldQuality
 * @param {{hasFreshValue: boolean, nowIso: string, currentLevel: string}} args
 * @return {{stale: boolean, lastGoodAt: (string|null), missedIntervals: number}}
 */
function updateFieldQuality(prevFieldQuality, {hasFreshValue, nowIso, currentLevel}) {
  const prev = prevFieldQuality || {stale: false, lastGoodAt: null, missedIntervals: 0};

  if (hasFreshValue) {
    return {stale: false, lastGoodAt: nowIso, missedIntervals: 0};
  }

  const missedIntervals = prev.missedIntervals + 1;
  const allowedMissedIntervals = currentLevel === 'normal' ? 2 : 1;

  return {
    stale: missedIntervals >= allowedMissedIntervals,
    lastGoodAt: prev.lastGoodAt,
    missedIntervals,
  };
}

const DATA_QUALITY_FIELDS = ['temperature', 'humidity', 'windSpeed', 'leafMoisture', 'light'];

/**
 * Advances data-quality tracking for every field the engine depends on.
 * `overallFlag` is 'sensor_unavailable' specifically when the primary
 * temperature sensor is stale (per spec: "if the primary temperature sensor
 * fails during an active warning, retain the current alert and display
 * Sensor data unavailable"), 'stale' for any other field, else 'ok'.
 *
 * `light` is included even though it's not itself a "display" field, because
 * derivations.isNightOrLowLight (which Rule 3A depends on) fails safe to
 * `false` on a missing reading - without tracking it here, a dead light
 * sensor could silently suppress Rule 3A and never trip the never-downgrade
 * guard in rules.js, since that guard keys off dataQualityOk.
 *
 * @param {Object|null|undefined} prevDataQuality
 * @param {Object} args
 * @param {Object} args.freshFields - {temperature, humidity, windSpeed, leafMoisture, light}:
 *   boolean, true if this tick had a usable value for that field.
 * @param {string} args.nowIso
 * @param {string} args.currentLevel
 * @return {Object} {temperature, humidity, windSpeed, leafMoisture, overallFlag}
 */
function updateDataQuality(prevDataQuality, {freshFields, nowIso, currentLevel}) {
  const prev = prevDataQuality || {};
  const next = {};

  for (const field of DATA_QUALITY_FIELDS) {
    next[field] = updateFieldQuality(prev[field], {
      hasFreshValue: !!freshFields[field],
      nowIso,
      currentLevel,
    });
  }

  const anyStale = DATA_QUALITY_FIELDS.some((field) => next[field].stale);
  next.overallFlag = next.temperature.stale ? 'sensor_unavailable' : (anyStale ? 'stale' : 'ok');

  return next;
}

/** @return {Object} Zero-valued event accumulators, used on reset. */
function createEmptyEventAccumulators() {
  return {
    minTempF: null,
    timeBelowCriticalMinutes: 0,
    timeBelow32Minutes: 0,
    timeBelow30Minutes: 0,
    maxCoolingRateFPerHr: null,
    firstBelowCriticalAt: null,
    recoveryStableMinutes: 0,
  };
}

/**
 * Advances the event/recovery duration accumulators for one tick. Purely a
 * function of temperature history - it does not know about alert levels.
 * The caller is responsible for swapping in a fresh `createEmptyEventAccumulators()`
 * once the engine fully returns to Normal, so these numbers describe "since
 * the current episode started" rather than accumulating forever.
 *
 * @param {Object|null|undefined} prevAccumulators
 * @param {Object} args
 * @param {number|null} args.budZoneTempF
 * @param {number|null} args.prevBudZoneTempF - Previous tick's bud-zone temp, for the stable-or-rising check.
 * @param {number|null} args.coolingRate60FPerHr
 * @param {Object} args.config - frostRuleConfig (criticalTempF, allClearMarginF).
 * @param {number|null} args.elapsedMinutes
 * @param {string} args.nowIso
 * @return {Object} Next eventAccumulators.
 */
function updateEventAccumulators(prevAccumulators, {
  budZoneTempF, prevBudZoneTempF, coolingRate60FPerHr, config, elapsedMinutes, nowIso,
}) {
  const prev = prevAccumulators || createEmptyEventAccumulators();
  if (budZoneTempF === null) return prev; // no reading this tick - hold as-is, don't reset or accumulate

  const minutes = elapsedMinutes === null ? 0 : elapsedMinutes;
  const criticalTempF = defaultIfNull(config.criticalTempF, 32);
  const allClearThresholdF = criticalTempF + defaultIfNull(config.allClearMarginF, 2);
  const belowCritical = budZoneTempF <= criticalTempF;

  const minTempF = prev.minTempF === null ? budZoneTempF : Math.min(prev.minTempF, budZoneTempF);

  // "Maximum cooling rate" = fastest drop = most negative signed rate, so we
  // track the running minimum of the signed value.
  const maxCoolingRateFPerHr = coolingRate60FPerHr === null ?
    prev.maxCoolingRateFPerHr :
    (prev.maxCoolingRateFPerHr === null ?
      coolingRate60FPerHr : Math.min(prev.maxCoolingRateFPerHr, coolingRate60FPerHr));

  const stableOrRising = prevBudZoneTempF === null || budZoneTempF >= prevBudZoneTempF;
  const recoveryStableMinutes = (budZoneTempF >= allClearThresholdF && stableOrRising) ?
    prev.recoveryStableMinutes + minutes : 0;

  return {
    minTempF,
    timeBelowCriticalMinutes: belowCritical ? prev.timeBelowCriticalMinutes + minutes : 0,
    timeBelow32Minutes: budZoneTempF <= 32 ? prev.timeBelow32Minutes + minutes : 0,
    timeBelow30Minutes: budZoneTempF <= 30 ? prev.timeBelow30Minutes + minutes : 0,
    maxCoolingRateFPerHr,
    firstBelowCriticalAt: belowCritical ? defaultIfNull(prev.firstBelowCriticalAt, nowIso) : null,
    recoveryStableMinutes,
  };
}

/**
 * Advances continuous-wetness duration tracking, given this tick's derived
 * wet/dry state from derivations.js's deriveLeafWetnessState.
 *
 * @param {Object|null|undefined} prevLeafWetness
 * @param {Object} args
 * @param {number|null} args.rawPercent
 * @param {string} args.state - 'wet' | 'dry'.
 * @param {boolean} args.justTransitionedDryToWet
 * @param {number|null} args.elapsedMinutes
 * @param {string} args.nowIso
 * @return {Object} {rawValue, state, stateSince, continuousWetnessMinutes, justTransitionedDryToWet}
 */
function updateLeafWetnessTracking(prevLeafWetness, {
  rawPercent, state, justTransitionedDryToWet, elapsedMinutes, nowIso,
}) {
  const prev = prevLeafWetness || {state: 'dry', stateSince: null, continuousWetnessMinutes: 0};
  const minutes = elapsedMinutes === null ? 0 : elapsedMinutes;
  const stateChanged = prev.state !== state;

  return {
    rawValue: rawPercent,
    state,
    stateSince: stateChanged ? nowIso : defaultIfNull(prev.stateSince, nowIso),
    continuousWetnessMinutes: state === 'wet' ?
      (stateChanged ? 0 : prev.continuousWetnessMinutes + minutes) : 0,
    justTransitionedDryToWet,
  };
}

module.exports = {
  computeElapsedMinutes,
  updateFieldQuality,
  updateDataQuality,
  createEmptyEventAccumulators,
  updateEventAccumulators,
  updateLeafWetnessTracking,
};
