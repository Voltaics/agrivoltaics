/**
 * ============================================================================
 * Frost Alert Notification Dispatch
 * ============================================================================
 *
 * Handles formatting and dispatching push notifications when the frost
 * engine's alert level transitions. Three responsibilities:
 *
 *   1. formatAlertMessage()  — Generates farmer-facing notification text
 *      matching the wording from the PDF specification for each alert level
 *      and freeze subtype (radiation, advective, mixed).
 *
 *   2. dispatchFrostNotification()  — Sends an FCM push notification to
 *      all devices subscribed to the zone's frost-alert topic, and logs
 *      every sent notification to a per-zone Firestore subcollection
 *      (frostAlertHistory) for audit and comparison reporting.
 *
 *   3. shouldNotify()  — Deduplication guard: prevents sending the same
 *      alert level notification twice within a configurable cooldown
 *      window (default: 15 min). This matters because the orchestrator
 *      may re-evaluate a zone faster than the notification cadence.
 *
 * No rule logic or sensor math lives here — this module only reads the
 * already-decided level and derived snapshot from evaluateZoneFrostEngine.
 */

const {db, messaging} = require('../firebase');
const {FieldValue} = require('firebase-admin/firestore');
const {defaultIfNull} = require('./utils');

// ============================================================================
// Constants
// ============================================================================

/**
 * Minimum minutes between sending two notifications for the SAME alert
 * level to the same zone, to avoid spamming farmers if the engine
 * re-evaluates rapidly. A level *change* always sends immediately.
 */
const NOTIFICATION_COOLDOWN_MINUTES = 15;

/**
 * Human-readable display names for each alert level, used in the
 * notification title bar.
 */
const LEVEL_TITLES = {
  normal: 'Normal',
  watch: 'Frost Watch',
  warning: 'Frost Warning',
  imminent: 'Frost Imminent',
  event: 'Freeze Event in Progress',
  allClear: 'All Clear',
};

// ============================================================================
// Message Formatting
// ============================================================================

/**
 * Formats the notification body text for a given alert level, following
 * the exact copy structure from Updated_Frost_Alert_Rules
 * PDF specification. Each level has prescribed wording that incorporates
 * live sensor values so the farmer gets actionable context without
 * opening the app.
 *
 * @param {string} level - One of the ALERT_LEVEL values from rules.js.
 * @param {string|null} subType - 'radiation', 'advective', or 'mixed'
 *   (only meaningful at the 'warning' level).
 * @param {Object} derivedSnapshot - The derivedSnapshot object from the
 *   engine state, containing live sensor values like airTempF,
 *   coolingRate60FPerHr, windSpeedMph, etc.
 * @param {Object} eventAccumulators - The event accumulator state,
 *   containing timeBelowCriticalMinutes and recoveryStableMinutes.
 * @param {Object} config - The zone's frostRuleConfig, used to read the
 *   farmer's configured critical temperature threshold.
 * @return {string} The formatted notification body text.
 */
function formatAlertMessage(level, subType, derivedSnapshot, eventAccumulators, config) {
  // Pull values with safe fallbacks for the message template
  const temp = derivedSnapshot.airTempF;
  const tempStr = temp !== null && temp !== undefined ? temp.toFixed(1) : '??';
  const rate = derivedSnapshot.coolingRate60FPerHr;
  const rateStr = rate !== null && rate !== undefined ? Math.abs(rate).toFixed(1) : '??';
  const wind = derivedSnapshot.windSpeedMph;
  const windStr = wind !== null && wind !== undefined ? wind.toFixed(1) : '??';
  const critTemp = defaultIfNull(config.criticalTempF, 32);

  switch (level) {
    // ----- Level 2: Frost Watch -----
    // The farmer should be alerted that conditions are trending cold,
    // but no action is needed yet. Wording per spec Section 2.
    case 'watch':
      return (
        `Frost Watch: Vineyard temperature is falling. ` +
        `Current temperature ${tempStr}°F, declining ${rateStr}°F/hour. ` +
        `Continue monitoring.`
      );

    // ----- Level 3: Frost Warning -----
    // Split by freeze type so the farmer knows *which* protection
    // strategy applies (wind machines vs. overhead irrigation, etc.).
    case 'warning':
      if (subType === 'advective') {
        return (
          `Advective Freeze Warning: A regional freeze is approaching. ` +
          `Bud-zone temperature is ${tempStr}°F and falling, ` +
          `sustained wind is ${windStr} mph, and the forecast indicates ` +
          `temperatures below the configured critical threshold of ` +
          `${critTemp}°F within two hours. ` +
          `Wind-based mixing may provide limited protection.`
        );
      }
      if (subType === 'mixed') {
        return (
          `Mixed Freeze Warning: Both radiation and advective freeze ` +
          `conditions detected. Bud-zone temperature is ${tempStr}°F ` +
          `and falling at ${rateStr}°F/hour with wind at ${windStr} mph. ` +
          `Prepare the approved frost-protection procedure.`
        );
      }
      // Default to radiation freeze (covers 'radiation' and null subType)
      return (
        `Radiation Freeze Warning: Bud-zone temperature is ${tempStr}°F ` +
        `and falling. Wind is calm, and conditions favor surface frost. ` +
        `The configured critical temperature of ${critTemp}°F may be ` +
        `reached within two hours. ` +
        `Prepare the approved frost-protection procedure.`
      );

    // ----- Level 4: Frost Imminent -----
    // The farmer must act NOW. Wording per spec Section 4.
    case 'imminent':
      return (
        `Frost Imminent: Measured bud-zone temperature has reached ` +
        `${tempStr}°F. The configured critical threshold is ${critTemp}°F. ` +
        `Initiate the vineyard's frost-protection procedure immediately.`
      );

    // ----- Level 5: Freeze Event in Progress -----
    // Includes the accumulated duration below critical for situational
    // awareness. Wording per spec Section 5.
    case 'event': {
      const duration = eventAccumulators && eventAccumulators.timeBelowCriticalMinutes
        ? Math.round(eventAccumulators.timeBelowCriticalMinutes)
        : 0;
      return (
        `Freeze Event in Progress: Bud-zone temperature has remained ` +
        `below the configured critical threshold of ${critTemp}°F ` +
        `for ${duration} minutes. Continue the vineyard's approved ` +
        `frost-protection procedure and monitoring.`
      );
    }

    // ----- Level 6: All Clear -----
    // The event has ended. Wording per spec Section 6.
    case 'allClear': {
      const stableMin = eventAccumulators && eventAccumulators.recoveryStableMinutes
        ? Math.round(eventAccumulators.recoveryStableMinutes)
        : 0;
      return (
        `All Clear: The current frost event has ended. ` +
        `Bud-zone temperature is above the configured critical threshold ` +
        `of ${critTemp}°F and has remained stable or rising for ` +
        `${stableMin} minutes. Continue routine monitoring.`
      );
    }

    // Normal does not generate a notification; included for completeness.
    default:
      return '';
  }
}

// ============================================================================
// Deduplication Guard
// ============================================================================

/**
 * Determines whether a notification should be sent for the given
 * transition. Returns true if:
 *   - The alert level actually changed (levelChanged === true), OR
 *   - The level hasn't changed but the last notification for this level
 *     was sent longer ago than the cooldown window (re-alert).
 *
 * Normal level never generates notifications — the farmer doesn't need
 * a push saying "nothing is happening."
 *
 * @param {Object} args
 * @param {string} args.newLevel - The frost engine's computed level.
 * @param {boolean} args.levelChanged - Whether the level changed this tick.
 * @param {string|null} args.lastNotifiedLevel - Level of the last sent notification.
 * @param {string|null} args.lastNotifiedAt - ISO timestamp of the last sent notification.
 * @param {string} args.nowIso - Current evaluation timestamp (ISO).
 * @param {boolean} [args.reNotifyOnSustained=false] - If true, re-notify for sustained elevated levels after cooldown.
 * @return {boolean}
 */
function shouldNotify({newLevel, levelChanged, lastNotifiedLevel, lastNotifiedAt, nowIso, reNotifyOnSustained = false}) {
  // Never notify for Normal — spec says no notification at Level 1.
  if (newLevel === 'normal') return false;

  // Always notify immediately on a level change.
  if (levelChanged) return true;

  // If we already notified for this exact level:
  if (lastNotifiedLevel === newLevel && lastNotifiedAt) {
    const lastMs = Date.parse(lastNotifiedAt);
    const nowMs = Date.parse(nowIso);
    if (Number.isFinite(lastMs) && Number.isFinite(nowMs)) {
      const elapsedMinutes = (nowMs - lastMs) / 60000;
      if (elapsedMinutes < NOTIFICATION_COOLDOWN_MINUTES) {
        return false;
      }
      // If past cooldown and caller requested sustained re-alerts, permit re-notifying
      if (reNotifyOnSustained) {
        return true;
      }
    }
  }

  return false;
}

// ============================================================================
// FCM Dispatch + Firestore Audit Log
// ============================================================================

/**
 * Sends an FCM push notification and writes an audit record to Firestore.
 *
 * FCM topic: `frost_alert_{organizationId}_{siteId}_{zoneId}`
 *   - The Flutter app subscribes to this topic per zone when the user
 *     enables frost alerts for that zone. This avoids needing to manage
 *     individual device tokens in the backend.
 *
 * Firestore audit path:
 *   organizations/{orgId}/sites/{siteId}/zones/{zoneId}/frostAlertHistory/{auto}
 *   - Each document records the level, subtype, matched rules, message
 *     text, and timestamp. The eventually added comparison report will read this
 *     collection to compute lead-time and false-positive metrics.
 *
 * @param {Object} args
 * @param {string} args.organizationId
 * @param {string} args.siteId
 * @param {string} args.zoneId
 * @param {string} args.level - New frost alert level.
 * @param {string|null} [args.previousLevel=null] - Previous frost alert level.
 * @param {string|null} args.subType - Warning subtype (radiation/advective/mixed).
 * @param {string[]} args.matchedRuleIds - Rule IDs that triggered this level.
 * @param {Object} args.derivedSnapshot - Sensor-derived values at the time of notification.
 * @param {Object} args.eventAccumulators - Duration accumulators for the active event.
 * @param {Object} args.config - Zone's frostRuleConfig.
 * @param {string} args.nowIso - ISO timestamp of the evaluation tick.
 * @return {Promise<{notified: boolean, messageId: string|null}>}
 */
async function dispatchFrostNotification({
  organizationId, siteId, zoneId, level, previousLevel, subType,
  matchedRuleIds, derivedSnapshot, eventAccumulators, config, nowIso,
}) {
  const title = LEVEL_TITLES[level] || 'Frost Alert';
  const body = formatAlertMessage(level, subType, derivedSnapshot, eventAccumulators, config);

  if (!body) {
    // No message body means this level doesn't warrant a notification
    // (e.g. 'normal'). This is a safety net — shouldNotify() should
    // have already filtered this out.
    return {notified: false, messageId: null};
  }

  // Build the FCM topic name. Topic names may only contain letters,
  // numbers, hyphens, and underscores — Firestore IDs already satisfy
  // these constraints, so no escaping is needed.
  const topic = `frost_alert_${organizationId}_${siteId}_${zoneId}`;

  // -- 1. Send FCM push notification --
  let messageId = null;
  try {
    messageId = await messaging.send({
      topic,
      notification: {
        title,
        body,
      },
      // Data payload for the Flutter app to parse programmatically
      // (e.g. navigate to the zone's frost detail screen on tap).
      data: {
        type: 'frost_alert',
        level,
        subType: subType || '',
        zoneId,
        siteId,
        organizationId,
        matchedRuleIds: JSON.stringify(matchedRuleIds),
        timestamp: nowIso,
      },
      // Android-specific: high priority so the notification is
      // delivered immediately even when the device is in Doze mode.
      android: {
        priority: 'high',
      },
      // APNs (iOS): mark as time-sensitive so it bypasses Focus modes.
      apns: {
        headers: {
          'apns-priority': '10',
        },
        payload: {
          aps: {
            sound: 'default',
            'interruption-level': 'time-sensitive',
          },
        },
      },
    });
  } catch (err) {
    // Log but do not throw — a failed push should not block the engine
    // from persisting state. Common causes: no subscribers on the topic
    // yet (returns a non-fatal error), or invalid topic name.
    console.error(
        `[frostEngine/notifications] FCM send failed for topic "${topic}":`,
        err.message || err,
    );
  }

  // -- 2. Write audit record to Firestore frostAlertHistory --
  // This collection is the primary data source for the future comparison
  // report, which joins these timestamped transitions against the AI
  // model's BigQuery frost_predictions to compute lead-time and FP/FN.
  try {
    if (db && typeof db.collection === 'function') {
      const historyRef = db.collection(
          `organizations/${organizationId}/sites/${siteId}/zones/${zoneId}/frostAlertHistory`,
      );

      const historyDoc = {
        level,
        previousLevel: previousLevel !== undefined ? previousLevel : null,
        subType: subType || null,
        matchedRuleIds: matchedRuleIds || [],
        message: body,
        fcmMessageId: messageId,
        fcmTopic: topic,
        derivedSnapshot: derivedSnapshot || {},
        createdAt: FieldValue.serverTimestamp(),
        evaluationTimestamp: nowIso,
      };

      await historyRef.add(historyDoc);
    }
  } catch (err) {
    console.error(
        `[frostEngine/notifications] Failed to write frostAlertHistory:`,
        err.message || err,
    );
  }

  return {notified: true, messageId};
}

// ============================================================================
// Exports
// ============================================================================

module.exports = {
  NOTIFICATION_COOLDOWN_MINUTES,
  LEVEL_TITLES,
  formatAlertMessage,
  shouldNotify,
  dispatchFrostNotification,
};

