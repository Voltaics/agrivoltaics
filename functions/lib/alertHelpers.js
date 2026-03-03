/**
 * Alert helper utilities for FCM push-notification alert evaluation.
 *
 * These functions are called from ingestSensorData after a successful
 * BigQuery insert to check alert rules and dispatch FCM notifications.
 */

const {db, messaging} = require('./firebase');

/**
 * Parse a 'HH:mm' time string into minutes since midnight.
 *
 * @param {string} timeStr
 * @return {number}
 */
function toMinutes(timeStr) {
  const [h, m] = timeStr.split(':').map(Number);
  return h * 60 + m;
}

/**
 * Returns true when the given UTC time falls within [start, end].
 * Supports overnight windows where start > end (e.g. 22:00 – 06:00).
 *
 * @param {Date} now
 * @param {string|null} start 'HH:mm'
 * @param {string|null} end   'HH:mm'
 * @return {boolean}
 */
function isWithinActiveWindow(now, start, end) {
  if (!start || !end) return true;

  const nowMin = now.getUTCHours() * 60 + now.getUTCMinutes();
  const startMin = toMinutes(start);
  const endMin = toMinutes(end);

  if (startMin <= endMin) {
    return nowMin >= startMin && nowMin <= endMin;
  }
  return nowMin >= startMin || nowMin <= endMin;
}

/**
 * Evaluate a comparison condition.
 *
 * @param {number} value
 * @param {string} operator
 * @param {number} threshold
 * @return {boolean}
 */
function evaluateAlertCondition(value, operator, threshold) {
  switch (operator) {
    case 'gt': return value > threshold;
    case 'lt': return value < threshold;
    case 'gte': return value >= threshold;
    case 'lte': return value <= threshold;
    case 'eq': return value === threshold;
    default: return false;
  }
}

/**
 * Fetch FCM tokens for a list of user IDs.
 * Returns an array of {uid, token} pairs for users that have a token stored.
 *
 * @param {string[]} userIds
 * @return {Promise<Array<{uid: string, token: string}>>}
 */
async function getFcmTokenPairs(userIds) {
  if (!userIds || userIds.length === 0) return [];

  const userDocs = await Promise.all(
      userIds.map((uid) => db.doc(`users/${uid}`).get()),
  );

  return userDocs
      .filter((doc) => doc.exists && doc.data().fcmToken)
      .map((doc) => ({uid: doc.id, token: doc.data().fcmToken}));
}

/**
 * Evaluate all enabled alert rules for the organisation against the freshly
 * ingested sensor readings and send FCM notifications where conditions are met.
 *
 * Called directly inside ingestSensorData after a successful BigQuery insert
 * so that alert evaluation happens in the same invocation rather than via a
 * separate Firestore-triggered function.
 *
 * @param {Object} args
 * @param {string} args.organizationId
 * @param {string} args.siteId
 * @param {string} args.zoneId
 * @param {Array<Object>} args.bqRows - Rows that were inserted to BigQuery.
 * @param {Date}   args.now           - Reference time for active-window check.
 * @return {Promise<void>}
 */
async function runAlertChecks({organizationId, siteId, zoneId, bqRows, now}) {
  const rulesSnap = await db
      .collection(`organizations/${organizationId}/alertRules`)
      .where('enabled', '==', true)
      .get();

  if (rulesSnap.empty) return;

  // Build a field→latestValue map from the ingested rows.
  // When multiple sensors report the same field, prefer the primary sensor;
  // otherwise use the newest value.
  const fieldValueMap = {};
  for (const row of bqRows) {
    const existing = fieldValueMap[row.field];
    const rowVal = typeof row.value === 'number' ? row.value : Number(row.value);
    if (Number.isNaN(rowVal)) continue;

    if (
      !existing ||
      (row.primarySensor && !existing.primarySensor) ||
      (row.primarySensor === existing.primarySensor && row.timestamp > existing.timestamp)
    ) {
      fieldValueMap[row.field] = {
        value: rowVal,
        unit: row.unit || '',
        sensorId: row.sensorId,
        timestamp: row.timestamp,
        primarySensor: row.primarySensor,
      };
    }
  }

  for (const ruleDoc of rulesSnap.docs) {
    const rule = ruleDoc.data();

    if (!isWithinActiveWindow(now, rule.activeTimeStart, rule.activeTimeEnd)) {
      console.log(`checkAlerts: rule "${rule.name}" outside active window, skipping`);
      continue;
    }

    const fieldEntry = fieldValueMap[rule.fieldAlias];
    if (!fieldEntry) continue;

    if (!evaluateAlertCondition(fieldEntry.value, rule.operator, rule.threshold)) continue;

    const tokenPairs = await getFcmTokenPairs(rule.notifyUserIds || []);
    if (tokenPairs.length === 0) {
      console.log(`checkAlerts: rule "${rule.name}" triggered but no FCM tokens found`);
      continue;
    }

    const tokens = tokenPairs.map((p) => p.token);
    const operatorLabel = {
      gt: '>', lt: '<', gte: '≥', lte: '≤', eq: '=',
    }[rule.operator] || rule.operator;

    const message = {
      notification: {
        title: `Alert: ${rule.name}`,
        body:
          `${rule.fieldAlias} ${operatorLabel} ${rule.threshold}${fieldEntry.unit} ` +
          `(current: ${fieldEntry.value}${fieldEntry.unit}) ` +
          `[${organizationId}/${siteId}/${zoneId}]`,
      },
      data: {
        organizationId,
        siteId,
        zoneId,
        sensorId: fieldEntry.sensorId,
        fieldAlias: rule.fieldAlias,
        value: String(fieldEntry.value),
        ruleId: ruleDoc.id,
      },
      tokens,
    };

    try {
      const response = await messaging.sendEachForMulticast(message);
      console.log(
          `checkAlerts: sent ${response.successCount} notifications for rule "${rule.name}"`,
          {failureCount: response.failureCount},
      );

      // Clear invalidated tokens
      if (response.failureCount > 0) {
        const clearOps = [];
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            const errCode = resp.error && resp.error.code;
            if (
              errCode === 'messaging/invalid-registration-token' ||
              errCode === 'messaging/registration-token-not-registered'
            ) {
              const badToken = tokens[idx];
              const pair = tokenPairs.find((p) => p.token === badToken);
              if (pair) {
                clearOps.push(db.doc(`users/${pair.uid}`).update({fcmToken: null}));
              }
            }
          }
        });
        if (clearOps.length > 0) {
          await Promise.all(clearOps);
          console.log(`checkAlerts: cleared ${clearOps.length} invalid FCM token(s)`);
        }
      }
    } catch (err) {
      console.error(
          `checkAlerts: failed to send notifications for rule "${rule.name}":`,
          err.message,
      );
    }
  }
}

module.exports = {runAlertChecks};
