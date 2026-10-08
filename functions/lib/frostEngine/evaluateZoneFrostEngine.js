/**
 * Orchestrates one frost-engine evaluation tick for a single zone: loads
 * config + prior state, fetches recent sensor context from BigQuery, runs
 * the pure derivations/accumulators/rules modules, and persists the result.
 *
 * Evaluations are throttled to roughly the spec's 15-minute cadence
 * (MIN_EVAL_INTERVAL_MINUTES) even though ingestSensorData can be called far
 * more often per zone (sensor boxes post on the order of every ~15s) - the
 * streak ("persist for 2 consecutive readings") and staleness ("after N
 * missed intervals") semantics in rules.js/accumulators.js are only
 * meaningful at that cadence, not on every raw HTTP POST.
 *
 * Forecast integration (functions/lib/frostEngine/forecast.js) is a later
 * phase - this orchestrator passes `forecast: null` for now, which rules.js
 * already treats as "omit that sub-condition" per the spec's own guidance.
 *
 * Notification dispatch on level transitions is also a later phase; this
 * module only detects and returns whether the level changed.
 */

const {db} = require('../firebase');
const derivations = require('./derivations');
const accumulators = require('./accumulators');
const {evaluateFrostLevel} = require('./rules');
const {loadEngineState, saveEngineState} = require('./stateStore');
const {fetchRecentEngineContext} = require('./context');
const {defaultIfNull, toNumberOrNull} = require('./utils');

const MIN_EVAL_INTERVAL_MINUTES = 10;

/**
 * @param {Object|undefined} fieldEntry - {value, unit, sensorId, timestamp, primarySensor} or undefined.
 * @return {number|null}
 */
function fieldValueOrNull(fieldEntry) {
  return fieldEntry ? toNumberOrNull(fieldEntry.value) : null;
}

/**
 * @param {Object} args
 * @param {string} args.organizationId
 * @param {string} args.siteId
 * @param {string} args.zoneId
 * @param {Date} args.now
 * @return {Promise<Object>} {skipped, reason, level, levelChanged, matchedRuleIds} -
 *   only `skipped` is always present; the rest depend on why/whether the tick ran.
 */
async function evaluateZoneFrostEngine({organizationId, siteId, zoneId, now}) {
  const nowIso = now.toISOString();

  const zoneDocRef = db.doc(`organizations/${organizationId}/sites/${siteId}/zones/${zoneId}`);
  const zoneDoc = await zoneDocRef.get();
  if (!zoneDoc.exists) return {skipped: true, reason: 'zone_not_found'};

  const zoneData = zoneDoc.data();
  const config = zoneData.frostRuleConfig || {};
  if (config.enabled !== true) return {skipped: true, reason: 'disabled'};

  const state = await loadEngineState({organizationId, siteId, zoneId, nowIso});

  const elapsedMinutes = accumulators.computeElapsedMinutes(state.lastEvalIso, nowIso);
  if (elapsedMinutes !== null && elapsedMinutes < MIN_EVAL_INTERVAL_MINUTES) {
    return {skipped: true, reason: 'throttled', elapsedMinutes};
  }

  const context = await fetchRecentEngineContext({organizationId, siteId, zoneId, now});

  const airTempF = fieldValueOrNull(context.current.temperature);
  const humidityPct = fieldValueOrNull(context.current.humidity);
  const windSpeedMph = fieldValueOrNull(context.current.windSpeed);
  const leafRawPercent = fieldValueOrNull(context.current.leafMoisture);
  const lightLux = fieldValueOrNull(context.current.light);

  const dewPointF = derivations.computeDewPointF(airTempF, humidityPct);
  const dewPointSpreadF = derivations.computeDewPointSpreadF(airTempF, dewPointF);

  const temp15 = context.temperatureAt[15];
  const temp60 = context.temperatureAt[60];
  const coolingRate15FPerHr = (airTempF !== null && temp15) ?
    derivations.computeCoolingRateFPerHr(airTempF, temp15.value, 15) : null;
  const coolingRate60FPerHr = (airTempF !== null && temp60) ?
    derivations.computeCoolingRateFPerHr(airTempF, temp60.value, 60) : null;

  const projectedTemp2hF = derivations.computeProjectedTemp2hF(airTempF, coolingRate60FPerHr);
  const windClass = derivations.classifyWind(windSpeedMph, config);
  const isNightOrLowLight = derivations.isNightOrLowLight(lightLux, config);

  const prevLeafState = state.leafWetness ? state.leafWetness.state : null;
  const leafDerived = derivations.deriveLeafWetnessState(leafRawPercent, prevLeafState, config);
  const leafWetness = accumulators.updateLeafWetnessTracking(state.leafWetness, {
    rawPercent: leafDerived.rawPercent,
    state: leafDerived.state,
    justTransitionedDryToWet: leafDerived.justTransitionedDryToWet,
    elapsedMinutes,
    nowIso,
  });

  // Phase 1 assumption: no dedicated bud-zone sensor exists yet, so bud-zone
  // temperature is the zone's primary air-temperature reading (see plan §4
  // - this is expected to change once the hardware team adds a vine-height
  // sensor, at which point this line is where that reading would plug in).
  const budZoneTempF = airTempF;

  const dataQuality = accumulators.updateDataQuality(state.dataQuality, {
    freshFields: {
      temperature: !!context.current.temperature,
      humidity: !!context.current.humidity,
      windSpeed: !!context.current.windSpeed,
      leafMoisture: !!context.current.leafMoisture,
      light: !!context.current.light,
    },
    nowIso,
    currentLevel: state.currentLevel,
  });
  const dataQualityOk = dataQuality.overallFlag === 'ok';

  const prevBudZoneTempF = state.derivedSnapshot ?
    toNumberOrNull(state.derivedSnapshot.airTempF) : null;

  const eventAccumulators = accumulators.updateEventAccumulators(state.eventAccumulators, {
    budZoneTempF, prevBudZoneTempF, coolingRate60FPerHr, config, elapsedMinutes, nowIso,
  });

  const derived = {
    airTempF, dewPointF, dewPointSpreadF, coolingRate60FPerHr, projectedTemp2hF,
    windSpeedMph, isNightOrLowLight, leafWetness: leafDerived,
  };

  const growthStage = defaultIfNull(config.growthStage, 'dormant');
  const minutesInCurrentLevel = accumulators.computeElapsedMinutes(state.levelEnteredAt, nowIso);

  const evalResult = evaluateFrostLevel({
    derived,
    budZoneTempF,
    growthStage,
    forecast: null, // forecast.js lands in a later phase; rules.js omits forecast-dependent sub-conditions until then
    config,
    streaksInput: state.ruleStreaks,
    eventAccumulators,
    prevLevel: state.currentLevel,
    dataQualityOk,
    nowIso,
    minutesInCurrentLevel,
  });

  const levelChanged = evalResult.level !== state.currentLevel;

  // Episode accumulators reset once the engine is fully back to Normal;
  // otherwise they carry through Imminent/Event/All-Clear so post-event
  // values (min temp, time below threshold, etc.) stay visible per spec.
  const finalEventAccumulators = evalResult.level === 'normal' ?
    accumulators.createEmptyEventAccumulators() : eventAccumulators;

  // postEventLog is a frozen snapshot taken the moment the engine first
  // reaches All Clear (the event that just ended), kept visible through the
  // All-Clear hold period, then cleared once fully back to Normal.
  // eventAccumulators itself already carries live through Event/All-Clear,
  // so this is specifically "what the event looked like," not a duplicate
  // of the live numbers.
  let nextPostEventLog = state.postEventLog || null;
  if (evalResult.level === 'allClear' && state.currentLevel !== 'allClear') {
    nextPostEventLog = eventAccumulators;
  } else if (evalResult.level === 'normal') {
    nextPostEventLog = null;
  }

  const nextState = {
    currentLevel: evalResult.level,
    previousLevel: state.currentLevel,
    activeSubWarning: evalResult.subType,
    levelEnteredAt: levelChanged ? nowIso : defaultIfNull(state.levelEnteredAt, nowIso),
    lastNotifiedLevel: state.lastNotifiedLevel, // owned by the notification-dispatch phase, not this one

    ruleStreaks: evalResult.streaks,
    leafWetness,
    eventAccumulators: finalEventAccumulators,
    postEventLog: nextPostEventLog,

    dataQuality,
    derivedSnapshot: {
      airTempF, dewPointF, dewPointSpreadF,
      coolingRate15FPerHr, coolingRate60FPerHr, projectedTemp2hF,
      windSpeedMph, windClass: windClass.bucket, windClassLabel: windClass.label,
      continuousWetnessMinutes: leafWetness.continuousWetnessMinutes,
    },
    lastEvalIso: nowIso,
  };

  await saveEngineState({organizationId, siteId, zoneId, nextState});

  return {
    skipped: false,
    level: evalResult.level,
    levelChanged,
    matchedRuleIds: evalResult.matchedRuleIds,
  };
}

module.exports = {evaluateZoneFrostEngine, MIN_EVAL_INTERVAL_MINUTES};
