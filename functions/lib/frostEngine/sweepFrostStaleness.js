/**
 * ============================================================================
 * Scheduled Staleness-Sweep Cloud Function
 * ============================================================================
 *
 * Problem this solves:
 *   The frost engine (evaluateZoneFrostEngine.js) only runs when a sensor
 *   actively POSTs data via ingestSensorData. If a sensor box loses power,
 *   runs out of battery, or loses network connectivity, the engine simply
 *   stops being called — and the spec's staleness guards (accumulators.js's
 *   updateFieldQuality/updateDataQuality) are never triggered because they
 *   only execute inside an evaluation tick.
 *
 *   This means a zone could be stuck in "Frost Imminent" forever with the
 *   farmer believing conditions are still dangerous, OR stuck in "Normal"
 *   with the farmer unaware the sensor died during an actual frost.
 *
 * Solution:
 *   This scheduled Cloud Function runs every 15 minutes (matching the
 *   spec's reporting cadence). It queries Firestore for every zone with
 *   frostRuleConfig.enabled === true, checks how long it has been since
 *   the frost engine last evaluated that zone, and if the sensor has been
 *   dark for too long, it:
 *     1. Marks all data-quality fields as stale
 *     2. Sets the overallFlag to 'sensor_unavailable'
 *     3. Sends a push notification warning the farmer about the sensor
 *        failure (if the zone is at Watch or above)
 *     4. Persists the updated state back to Firestore
 *
 *   Critically, it does NOT change the alert level — the spec says
 *   "retain the current alert" when sensors fail. The never-downgrade
 *   guard in rules.js prevents lowering the level on stale data.
 *
 * Deployment:
 *   Export from functions/index.js as a scheduled function using
 *   firebase-functions/v2/scheduler.onSchedule, or wire it to
 *   Google Cloud Scheduler as an HTTP-triggered function.
 */

const functions = require('firebase-functions');
const {db, messaging} = require('../firebase');
const {FieldValue} = require('firebase-admin/firestore');
const {loadEngineState, saveEngineState} = require('./stateStore');
const accumulators = require('./accumulators');

// ============================================================================
// Configuration
// ============================================================================

/**
 * Staleness thresholds per spec (Updated_Frost_Alert_Rules.pdf, Section 'Data-quality'):
 * - During Normal operation, mark data stale after two missed reporting intervals (30 minutes).
 * - During Frost Watch or any higher alert level, mark data stale after one missed reporting interval (15 minutes).
 */
const STALENESS_THRESHOLD_NORMAL_MINUTES = 30;
const STALENESS_THRESHOLD_ELEVATED_MINUTES = 15;
const STALENESS_THRESHOLD_MINUTES = 30; // Default / backwards compatibility alias

/**
 * Returns the staleness threshold in minutes for a given alert level per spec.
 *
 * @param {string} currentLevel
 * @param {Object} [config]
 * @return {number}
 */
function getStalenessThresholdMinutes(currentLevel, config) {
  const interval = (config && typeof config.reportingIntervalMinutes === 'number')
    ? config.reportingIntervalMinutes
    : 15;
  const allowedMissed = currentLevel === 'normal' ? 2 : 1;
  return interval * allowedMissed;
}

/**
 * Minimum minutes between sensor-unavailable push notifications for
 * the same zone, to prevent hourly spam if a sensor stays dead.
 */
const SENSOR_ALERT_COOLDOWN_MINUTES = 60;

// ============================================================================
// Core Sweep Logic (exported for unit testing)
// ============================================================================

/**
 * Scans all organizations → sites → zones for enabled frost rule
 * configs and checks each zone's frost engine state for staleness.
 *
 * This function is pure I/O orchestration — all the actual staleness
 * logic is delegated to accumulators.updateDataQuality() which already
 * implements the spec's "2 missed intervals in Normal, 1 missed interval
 * at Watch or higher" rule.
 *
 * @return {Promise<{zonesChecked: number, zonesStale: number, errors: string[]}>}
 */
async function sweepAllZonesForStaleness() {
  const nowIso = new Date().toISOString();
  let zonesChecked = 0;
  let zonesStale = 0;
  const errors = [];

  // Query all organizations. In production the vineyard has one org,
  // but this is written to scale if additional sites are added.
  let orgsSnapshot;
  try {
    orgsSnapshot = await db.collection('organizations').get();
  } catch (err) {
    console.error('[sweepFrostStaleness] Failed to list organizations:', err.message);
    return {zonesChecked: 0, zonesStale: 0, errors: [err.message]};
  }

  for (const orgDoc of orgsSnapshot.docs) {
    const orgId = orgDoc.id;

    let sitesSnapshot;
    try {
      sitesSnapshot = await db.collection(`organizations/${orgId}/sites`).get();
    } catch (err) {
      errors.push(`Failed to list sites for org ${orgId}: ${err.message}`);
      continue;
    }

    for (const siteDoc of sitesSnapshot.docs) {
      const siteId = siteDoc.id;

      let zonesSnapshot;
      try {
        zonesSnapshot = await db.collection(
            `organizations/${orgId}/sites/${siteId}/zones`,
        ).get();
      } catch (err) {
        errors.push(`Failed to list zones for ${orgId}/${siteId}: ${err.message}`);
        continue;
      }

      for (const zoneDoc of zonesSnapshot.docs) {
        const zoneId = zoneDoc.id;
        const zoneData = zoneDoc.data();
        const config = zoneData.frostRuleConfig || {};

        // Only sweep zones that have the frost engine enabled.
        if (config.enabled !== true) continue;

        zonesChecked++;

        try {
          const stale = await checkAndUpdateZoneStaleness({
            organizationId: orgId,
            siteId,
            zoneId,
            config,
            nowIso,
          });
          if (stale) zonesStale++;
        } catch (err) {
          errors.push(`Error sweeping ${orgId}/${siteId}/${zoneId}: ${err.message}`);
        }
      }
    }
  }

  console.log(
      `[sweepFrostStaleness] Checked ${zonesChecked} zones, ` +
      `${zonesStale} stale, ${errors.length} errors.`,
  );

  return {zonesChecked, zonesStale, errors};
}

/**
 * Checks a single zone's frost engine state for staleness and updates
 * the data-quality flags if the engine has been silent too long.
 *
 * @param {Object} args
 * @param {string} args.organizationId
 * @param {string} args.siteId
 * @param {string} args.zoneId
 * @param {Object} args.config - The zone's frostRuleConfig.
 * @param {string} args.nowIso - Current timestamp (ISO).
 * @return {Promise<boolean>} True if the zone was flagged as stale.
 */
async function checkAndUpdateZoneStaleness({
  organizationId, siteId, zoneId, config, nowIso,
}) {
  const state = await loadEngineState({organizationId, siteId, zoneId, nowIso});

  // Compute how long since the engine last ran a full evaluation tick.
  const elapsedMinutes = accumulators.computeElapsedMinutes(
      state.lastEvalIso,
      nowIso,
  );

  // If lastEvalIso is null (zone has never been evaluated) or the
  // elapsed time is under the staleness threshold, nothing to do.
  const thresholdMinutes = getStalenessThresholdMinutes(state.currentLevel, config);
  if (elapsedMinutes === null || elapsedMinutes < thresholdMinutes) {
    return false;
  }

  // --- Zone is stale: sensors have not reported for too long ---

  // Advance data-quality trackers with ALL fields marked as not fresh.
  // This triggers the spec's "mark stale after N missed intervals" rule
  // inside updateDataQuality. We call it once per sweep interval
  // (15 min), which effectively simulates a "missed evaluation tick."
  const dataQuality = accumulators.updateDataQuality(state.dataQuality, {
    freshFields: {
      temperature: false,
      humidity: false,
      windSpeed: false,
      leafMoisture: false,
      light: false,
    },
    nowIso,
    currentLevel: state.currentLevel,
  });

  // Build the updated state. We do NOT change the alert level here —
  // the spec says "retain the current alert" when sensors fail. The
  // never-downgrade guard in rules.js will prevent any future tick
  // from lowering the level while dataQualityOk is false.
  const nextState = Object.assign({}, state, {
    dataQuality,
    // Update lastEvalIso so the sweep doesn't re-fire every 15 min
    // against the same ancient timestamp. This also means the next
    // sweep will measure elapsed time from THIS sweep, not from the
    // last real sensor evaluation.
    lastEvalIso: nowIso,
  });

  await saveEngineState({organizationId, siteId, zoneId, nextState});

  // --- Send a sensor-unavailable push notification ---
  // Only send if the zone is at Watch or above (sensor death during
  // Normal is less urgent) and we haven't already sent one recently.
  const isElevated = state.currentLevel !== 'normal';
  const cooldownOk = !state.lastSensorAlertAt || (() => {
    const lastMs = Date.parse(state.lastSensorAlertAt);
    const nowMs = Date.parse(nowIso);
    return Number.isFinite(lastMs) && Number.isFinite(nowMs) &&
      (nowMs - lastMs) / 60000 >= SENSOR_ALERT_COOLDOWN_MINUTES;
  })();

  if (isElevated && cooldownOk) {
    const topic = `frost_alert_${organizationId}_${siteId}_${zoneId}`;
    const body =
      `Sensor Data Unavailable: The frost engine has not received ` +
      `sensor data for zone "${zoneId}" in ${Math.round(elapsedMinutes)} ` +
      `minutes. The current alert level (${state.currentLevel}) is ` +
      `being retained. Please check sensor hardware and connectivity.`;

    try {
      await messaging.send({
        topic,
        notification: {
          title: 'Sensor Data Unavailable',
          body,
        },
        data: {
          type: 'sensor_unavailable',
          zoneId,
          siteId,
          organizationId,
          currentLevel: state.currentLevel,
          minutesSinceLastEval: String(Math.round(elapsedMinutes)),
          timestamp: nowIso,
        },
        android: {priority: 'high'},
      });

      // Record the send time so we don't spam the farmer
      await saveEngineState({
        organizationId, siteId, zoneId,
        nextState: Object.assign({}, nextState, {
          lastSensorAlertAt: nowIso,
        }),
      });
    } catch (err) {
      console.error(
          `[sweepFrostStaleness] FCM send failed for ${zoneId}:`,
          err.message || err,
      );
    }
  }

  return true;
}

// ============================================================================
// Cloud Function Export
// ============================================================================

/**
 * The scheduled Cloud Function entry point. Deploy as:
 *   exports.sweepFrostStaleness = sweepFrostStaleness;
 * in functions/index.js.
 *
 * Configured to run every 15 minutes via Google Cloud Scheduler.
 * The schedule string 'every 15 minutes' is interpreted by
 * firebase-functions v2's onSchedule, or you can use a standard
 * cron expression '* /15 * * * *' with Cloud Scheduler directly.
 */
const sweepFrostStaleness = functions.pubsub
    .schedule('every 15 minutes')
    .onRun(async (context) => {
      console.log('[sweepFrostStaleness] Starting scheduled staleness sweep...');
      const result = await sweepAllZonesForStaleness();
      console.log('[sweepFrostStaleness] Complete:', JSON.stringify(result));
      return null;
    });

module.exports = {
  sweepFrostStaleness,
  // Exported for unit testing:
  sweepAllZonesForStaleness,
  checkAndUpdateZoneStaleness,
  getStalenessThresholdMinutes,
  STALENESS_THRESHOLD_NORMAL_MINUTES,
  STALENESS_THRESHOLD_ELEVATED_MINUTES,
  STALENESS_THRESHOLD_MINUTES,
  SENSOR_ALERT_COOLDOWN_MINUTES,
};

