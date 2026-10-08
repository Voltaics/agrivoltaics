/**
 * Firestore I/O for the frost engine's per-zone runtime state
 * (frostEngineState/current). All decision logic lives in rules.js and
 * accumulators.js - this module only loads the previous state and persists
 * whatever the orchestrator (evaluateZoneFrostEngine.js) decides next.
 */

const {db} = require('../firebase');
const {FieldValue} = require('firebase-admin/firestore');
const {createEmptyEventAccumulators} = require('./accumulators');

/**
 * @param {string} orgId
 * @param {string} siteId
 * @param {string} zoneId
 * @return {FirebaseFirestore.DocumentReference}
 */
function engineStateDocRef(orgId, siteId, zoneId) {
  return db.doc(
      `organizations/${orgId}/sites/${siteId}/zones/${zoneId}/frostEngineState/current`,
  );
}

/**
 * @param {string} nowIso
 * @return {Object} A fresh frostEngineState/current shape, used the first
 *   time a zone is evaluated (no prior doc exists yet).
 */
function createDefaultEngineState(nowIso) {
  return {
    currentLevel: 'normal',
    previousLevel: null,
    activeSubWarning: null,
    levelEnteredAt: nowIso,
    lastNotifiedLevel: null,

    ruleStreaks: {
      rule3A: {consecutiveTrue: 0, lastTrueAt: null, lastEvalAt: null},
      rule3B: {consecutiveTrue: 0, lastTrueAt: null, lastEvalAt: null},
      rule3C: {consecutiveTrue: 0, lastTrueAt: null, lastEvalAt: null},
    },

    leafWetness: {
      rawValue: null, state: 'dry', stateSince: null,
      continuousWetnessMinutes: 0, justTransitionedDryToWet: false,
    },

    eventAccumulators: createEmptyEventAccumulators(),
    postEventLog: null,

    dataQuality: {
      temperature: {stale: false, lastGoodAt: null, missedIntervals: 0},
      humidity: {stale: false, lastGoodAt: null, missedIntervals: 0},
      windSpeed: {stale: false, lastGoodAt: null, missedIntervals: 0},
      leafMoisture: {stale: false, lastGoodAt: null, missedIntervals: 0},
      light: {stale: false, lastGoodAt: null, missedIntervals: 0},
      overallFlag: 'ok',
    },

    derivedSnapshot: {},
    lastEvalIso: null, // null (not nowIso) so the very first real tick is never throttled
  };
}

/**
 * @param {Object} args
 * @param {string} args.organizationId
 * @param {string} args.siteId
 * @param {string} args.zoneId
 * @param {string} args.nowIso
 * @return {Promise<Object>} Current state - a fresh default (not yet persisted) if no doc exists yet.
 */
async function loadEngineState({organizationId, siteId, zoneId, nowIso}) {
  const snapshot = await engineStateDocRef(organizationId, siteId, zoneId).get();
  if (!snapshot.exists) {
    return createDefaultEngineState(nowIso);
  }
  return snapshot.data();
}

/**
 * Persists a fully-computed next state. The orchestrator assembles the
 * complete object every tick, so this is a plain overwrite (not a partial
 * merge) aside from the server-timestamp field.
 *
 * @param {Object} args
 * @param {string} args.organizationId
 * @param {string} args.siteId
 * @param {string} args.zoneId
 * @param {Object} args.nextState
 * @return {Promise<void>}
 */
async function saveEngineState({organizationId, siteId, zoneId, nextState}) {
  const docRef = engineStateDocRef(organizationId, siteId, zoneId);
  await docRef.set(Object.assign({}, nextState, {updatedAt: FieldValue.serverTimestamp()}));
}

module.exports = {
  createDefaultEngineState,
  loadEngineState,
  saveEngineState,
};
