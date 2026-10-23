/**
 * ============================================================================
 * Authenticated Manual Test-Trigger Endpoint
 * ============================================================================
 *
 * Problem this solves:
 *   There is no way to test or demonstrate frost alert transitions without
 *   waiting for actual freezing weather or injecting fake sensor hardware
 *   packets into BigQuery. This makes QA, CI integration testing, and
 *   demonstrations unreliable and weather-dependent.
 *
 * Solution:
 *   An authenticated HTTP Cloud Function that accepts simulated sensor
 *   readings or a forced alert level, runs them through the same
 *   evaluateZoneFrostEngine orchestrator (or directly mutates state for
 *   UI testing), and returns the result. Two modes:
 *
 *   Mode A: "simulate_readings"
 *     Injects mock sensor values into the engine's derivation pipeline
 *     so rules fire organically. Tests the full rule → notification chain.
 *
 *   Mode B: "force_level"
 *     Directly writes the requested alert level to frostEngineState/current
 *     and fires a notification. Tests the Flutter client's alert banner,
 *     card rendering, and notification handling without needing valid
 *     sensor math.
 *
 * Security:
 *   Reuses the existing verifyAuthHeader/isOrgMember pattern from
 *   functions/lib/http.js. Only authenticated members of the specified
 *   organization can trigger test alerts for that org's zones.
 */

const functions = require('firebase-functions');
const {db} = require('../firebase');
const {FieldValue} = require('firebase-admin/firestore');
const {handlePreflightAndMethod, verifyAuthHeader, isOrgMember} = require('../http');
const {loadEngineState, saveEngineState} = require('./stateStore');
const {ALERT_LEVEL} = require('./rules');
const {dispatchFrostNotification, formatAlertMessage} = require('./notifications');
const {defaultIfNull} = require('./utils');

// ============================================================================
// Valid alert levels for the "force_level" mode. Listed explicitly so we
// can validate the caller's input before writing to Firestore.
// ============================================================================
const VALID_LEVELS = new Set([
  'normal', 'watch', 'warning', 'imminent', 'event', 'allClear',
]);

const VALID_SUBTYPES = new Set([
  'radiation', 'advective', 'mixed',
]);

// ============================================================================
// HTTP Handler
// ============================================================================

/**
 * The Cloud Function handler. Expects a POST request with JSON body:
 *
 * Common fields (both modes):
 *   - organizationId: string (required)
 *   - siteId: string (required)
 *   - zoneId: string (required)
 *   - mode: "simulate_readings" | "force_level" (required)
 *
 * Mode "simulate_readings" additional fields:
 *   - mockReadings: {
 *       airTempF?: number,
 *       humidity?: number,
 *       windSpeed?: number,
 *       leafMoisture?: number,
 *       light?: number,
 *       coolingRate60FPerHr?: number,
 *       projectedTemp2hF?: number,
 *       dewPointSpreadF?: number,
 *     }
 *   These are injected into the derivation pipeline in place of real
 *   sensor values. Any omitted fields default to null (sensor missing).
 *
 * Mode "force_level" additional fields:
 *   - targetLevel: string (required) - one of the VALID_LEVELS
 *   - subType: string (optional) - 'radiation', 'advective', or 'mixed'
 *   - sendNotification: boolean (optional, default true) - whether to
 *     also dispatch an FCM notification for the forced level
 *
 * Response: {success: boolean, result: Object}
 */
async function handleTestTrigger(req, res) {
  // --- CORS + method guard ---
  if (handlePreflightAndMethod(req, res)) return;

  // --- Authentication ---
  const decodedToken = await verifyAuthHeader(req);
  if (!decodedToken) {
    res.status(401).json({
      success: false,
      error: 'Missing or invalid Authorization header. Include a valid Firebase ID token.',
    });
    return;
  }

  // --- Parse + validate request body ---
  const {organizationId, siteId, zoneId, mode} = req.body || {};

  if (!organizationId || !siteId || !zoneId || !mode) {
    res.status(400).json({
      success: false,
      error: 'Missing required fields: organizationId, siteId, zoneId, mode.',
    });
    return;
  }

  // --- Authorization: caller must be a member of the organization ---
  const isMember = await isOrgMember(organizationId, decodedToken.uid);
  if (!isMember) {
    res.status(403).json({
      success: false,
      error: 'You are not a member of this organization.',
    });
    return;
  }

  // --- Verify the zone exists and has frost rules enabled ---
  const zoneDocRef = db.doc(
      `organizations/${organizationId}/sites/${siteId}/zones/${zoneId}`,
  );
  const zoneDoc = await zoneDocRef.get();
  if (!zoneDoc.exists) {
    res.status(404).json({
      success: false,
      error: `Zone ${zoneId} not found in site ${siteId}.`,
    });
    return;
  }

  const zoneData = zoneDoc.data();
  const config = zoneData.frostRuleConfig || {};

  // --- Route to the requested mode ---
  try {
    let result;
    if (mode === 'force_level') {
      result = await handleForceLevel({
        organizationId, siteId, zoneId, config, body: req.body,
      });
    } else if (mode === 'simulate_readings') {
      result = await handleSimulateReadings({
        organizationId, siteId, zoneId, config, body: req.body,
      });
    } else {
      res.status(400).json({
        success: false,
        error: `Invalid mode "${mode}". Use "simulate_readings" or "force_level".`,
      });
      return;
    }

    res.status(200).json({success: true, result});
  } catch (err) {
    console.error('[testTriggerFrostAlert] Unhandled error:', err);
    res.status(500).json({
      success: false,
      error: err.message || 'Internal server error.',
    });
  }
}

// ============================================================================
// Mode A: simulate_readings
// ============================================================================

/**
 * Builds a mock "derived snapshot" from the caller's mock sensor values
 * and feeds it through the frost rule evaluator. This mode exercises the
 * full rule chain → notification pipeline, so it tests exactly the same
 * code path as a real sensor ingest would trigger.
 *
 * The key difference from a real evaluation is that we don't query
 * BigQuery for sensor context — we use the caller's mock values directly.
 * Everything downstream (rules, accumulators, notifications) is real.
 */
async function handleSimulateReadings({organizationId, siteId, zoneId, config, body}) {
  const nowIso = new Date().toISOString();
  const mock = body.mockReadings || {};

  // Lazy-require to avoid circular dependency — evaluateZoneFrostEngine
  // imports notifications.js which is a peer of this file.
  const derivations = require('./derivations');
  const {evaluateFrostLevel} = require('./rules');
  const accumulators = require('./accumulators');
  const {shouldNotify, dispatchFrostNotification} = require('./notifications');

  // Load the zone's current frost engine state so rules that depend
  // on prior state (streaks, accumulators, recovery gating) work correctly.
  const state = await loadEngineState({organizationId, siteId, zoneId, nowIso});

  // Build derived values from mock readings, filling in what the caller
  // didn't provide with null (sensor missing).
  const airTempF = mock.airTempF !== undefined ? mock.airTempF : null;
  const humidityPct = mock.humidity !== undefined ? mock.humidity : null;
  const windSpeedMph = mock.windSpeed !== undefined ? mock.windSpeed : null;
  const leafRawPercent = mock.leafMoisture !== undefined ? mock.leafMoisture : null;
  const lightLux = mock.light !== undefined ? mock.light : null;

  const dewPointF = derivations.computeDewPointF(airTempF, humidityPct);
  const dewPointSpreadF = mock.dewPointSpreadF !== undefined
    ? mock.dewPointSpreadF
    : derivations.computeDewPointSpreadF(airTempF, dewPointF);

  const coolingRate60FPerHr = mock.coolingRate60FPerHr !== undefined
    ? mock.coolingRate60FPerHr
    : null;

  const projectedTemp2hF = mock.projectedTemp2hF !== undefined
    ? mock.projectedTemp2hF
    : derivations.computeProjectedTemp2hF(airTempF, coolingRate60FPerHr);

  const isNightOrLowLight = derivations.isNightOrLowLight(lightLux, config);
  const prevLeafState = state.leafWetness ? state.leafWetness.state : null;
  const leafDerived = derivations.deriveLeafWetnessState(leafRawPercent, prevLeafState, config);

  const budZoneTempF = airTempF;
  const elapsedMinutes = accumulators.computeElapsedMinutes(state.lastEvalIso, nowIso);

  const dataQuality = accumulators.updateDataQuality(state.dataQuality, {
    freshFields: {
      temperature: airTempF !== null,
      humidity: humidityPct !== null,
      windSpeed: windSpeedMph !== null,
      leafMoisture: leafRawPercent !== null,
      light: lightLux !== null,
    },
    nowIso,
    currentLevel: state.currentLevel,
  });

  const eventAccumulators = accumulators.updateEventAccumulators(state.eventAccumulators, {
    budZoneTempF,
    prevBudZoneTempF: state.derivedSnapshot ? state.derivedSnapshot.airTempF : null,
    coolingRate60FPerHr,
    config,
    elapsedMinutes,
    nowIso,
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
    forecast: null,
    config,
    streaksInput: state.ruleStreaks,
    eventAccumulators,
    prevLevel: state.currentLevel,
    dataQualityOk: dataQuality.overallFlag === 'ok',
    nowIso,
    minutesInCurrentLevel,
  });

  const levelChanged = evalResult.level !== state.currentLevel;

  // Build the derived snapshot for persistence and notification formatting
  const derivedSnapshot = {
    airTempF, dewPointF, dewPointSpreadF, coolingRate60FPerHr, projectedTemp2hF,
    windSpeedMph, windClass: null, windClassLabel: null,
    continuousWetnessMinutes: 0,
  };

  // Persist the new state so the UI updates and subsequent evaluations
  // see the effect of this test trigger.
  const leafWetness = accumulators.updateLeafWetnessTracking(state.leafWetness, {
    rawPercent: leafDerived.rawPercent,
    state: leafDerived.state,
    justTransitionedDryToWet: leafDerived.justTransitionedDryToWet,
    elapsedMinutes,
    nowIso,
  });

  const finalEventAccumulators = evalResult.level === 'normal'
    ? accumulators.createEmptyEventAccumulators()
    : eventAccumulators;

  const nextState = {
    currentLevel: evalResult.level,
    previousLevel: state.currentLevel,
    activeSubWarning: evalResult.subType,
    levelEnteredAt: levelChanged ? nowIso : defaultIfNull(state.levelEnteredAt, nowIso),
    lastNotifiedLevel: state.lastNotifiedLevel,
    ruleStreaks: evalResult.streaks,
    leafWetness,
    eventAccumulators: finalEventAccumulators,
    postEventLog: state.postEventLog,
    dataQuality,
    derivedSnapshot,
    lastEvalIso: nowIso,
  };

  await saveEngineState({organizationId, siteId, zoneId, nextState});

  // Fire notification if level changed
  let notified = false;
  if (levelChanged && evalResult.level !== 'normal') {
    const notifResult = await dispatchFrostNotification({
      organizationId, siteId, zoneId,
      level: evalResult.level,
      previousLevel: state.currentLevel,
      subType: evalResult.subType,
      matchedRuleIds: evalResult.matchedRuleIds,
      derivedSnapshot,
      eventAccumulators: finalEventAccumulators,
      config,
      nowIso,
    });
    notified = notifResult.notified;
  }

  return {
    mode: 'simulate_readings',
    previousLevel: state.currentLevel,
    newLevel: evalResult.level,
    levelChanged,
    subType: evalResult.subType,
    matchedRuleIds: evalResult.matchedRuleIds,
    notified,
    derivedSnapshot,
  };
}

// ============================================================================
// Mode B: force_level
// ============================================================================

/**
 * Directly sets the zone's frost engine state to the requested alert
 * level without running any sensor derivation or rule evaluation.
 *
 * This mode is for UI testing: it lets you verify that the Flutter app
 * correctly renders alert banners, colors, and notification cards for
 * every level without needing sensor math to cooperate.
 *
 * Optionally dispatches an FCM notification for the forced level so the
 * notification rendering can also be tested.
 */
async function handleForceLevel({organizationId, siteId, zoneId, config, body}) {
  const nowIso = new Date().toISOString();
  const {targetLevel, subType, sendNotification} = body;

  // Validate targetLevel
  if (!targetLevel || !VALID_LEVELS.has(targetLevel)) {
    throw new Error(
        `Invalid targetLevel "${targetLevel}". ` +
        `Must be one of: ${Array.from(VALID_LEVELS).join(', ')}`,
    );
  }

  // Validate subType if provided
  if (subType && !VALID_SUBTYPES.has(subType)) {
    throw new Error(
        `Invalid subType "${subType}". ` +
        `Must be one of: ${Array.from(VALID_SUBTYPES).join(', ')}`,
    );
  }

  // Load current state so we can report what changed
  const state = await loadEngineState({organizationId, siteId, zoneId, nowIso});
  const levelChanged = targetLevel !== state.currentLevel;

  // Build a minimal derived snapshot for the notification formatter.
  // Since this is a forced level, we use placeholder values.
  const derivedSnapshot = state.derivedSnapshot || {
    airTempF: null, dewPointF: null, dewPointSpreadF: null,
    coolingRate60FPerHr: null, projectedTemp2hF: null,
    windSpeedMph: null, windClass: null,
  };

  // Write the forced level to the engine state
  const nextState = Object.assign({}, state, {
    currentLevel: targetLevel,
    previousLevel: state.currentLevel,
    activeSubWarning: subType || null,
    levelEnteredAt: levelChanged ? nowIso : state.levelEnteredAt,
    lastEvalIso: nowIso,
  });

  await saveEngineState({organizationId, siteId, zoneId, nextState});

  // Optionally dispatch a notification (defaults to true)
  let notified = false;
  const shouldSend = sendNotification !== false && targetLevel !== 'normal';
  if (shouldSend) {
    const notifResult = await dispatchFrostNotification({
      organizationId, siteId, zoneId,
      level: targetLevel,
      previousLevel: state.currentLevel,
      subType: subType || null,
      matchedRuleIds: ['test_trigger_forced'],
      derivedSnapshot,
      eventAccumulators: state.eventAccumulators || {},
      config,
      nowIso,
    });
    notified = notifResult.notified;
  }

  return {
    mode: 'force_level',
    previousLevel: state.currentLevel,
    newLevel: targetLevel,
    subType: subType || null,
    levelChanged,
    notified,
  };
}

// ============================================================================
// Cloud Function Export
// ============================================================================

/**
 * Export as an HTTP Cloud Function. Add to functions/index.js:
 *   const {testTriggerFrostAlert} = require('./lib/frostEngine/testTriggerFrostAlert');
 *   exports.testTriggerFrostAlert = testTriggerFrostAlert;
 */
const testTriggerFrostAlert = functions.https.onRequest(handleTestTrigger);

module.exports = {
  testTriggerFrostAlert,
  // Exported for unit testing:
  handleTestTrigger,
  handleForceLevel,
  handleSimulateReadings,
};

