/**
 * checkAlerts – Firestore-triggered Cloud Function
 *
 * Fires whenever a sensor document is updated
 * (organizations/{orgId}/sites/{siteId}/zones/{zoneId}/sensors/{sensorId}).
 *
 * For every enabled AlertRule defined on the organization, this function:
 *   1. Verifies the rule is enabled.
 *   2. Verifies the current time is within the rule's optional active window.
 *   3. Evaluates the condition against the updated sensor field value.
 *   4. Collects FCM tokens for the users listed in notifyUserIds.
 *   5. Sends an FCM notification via firebase-admin's messaging API.
 *
 * AlertRule document schema (organizations/{orgId}/alertRules/{ruleId}):
 * {
 *   name: string,
 *   fieldAlias: string,          // e.g. 'temperature'
 *   operator: 'gt'|'lt'|'gte'|'lte'|'eq',
 *   threshold: number,
 *   enabled: boolean,
 *   notifyUserIds: string[],
 *   activeTimeStart: string|null, // 'HH:mm' 24-hour, e.g. '22:00'
 *   activeTimeEnd: string|null,   // 'HH:mm' 24-hour, e.g. '06:00'
 * }
 */

const functions = require('firebase-functions');
const {db, messaging} = require('../lib/firebase');

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
 * Returns true when the current UTC time falls within [start, end].
 * Supports overnight windows where start > end (e.g. 22:00 – 06:00).
 *
 * @param {Date} now
 * @param {string|null} start 'HH:mm'
 * @param {string|null} end   'HH:mm'
 * @return {boolean}
 */
function isWithinActiveWindow(now, start, end) {
  if (!start || !end) return true; // no window configured → always active

  const nowMin = now.getUTCHours() * 60 + now.getUTCMinutes();
  const startMin = toMinutes(start);
  const endMin = toMinutes(end);

  if (startMin <= endMin) {
    // Same-day window, e.g. 08:00 – 18:00
    return nowMin >= startMin && nowMin <= endMin;
  } else {
    // Overnight window, e.g. 22:00 – 06:00
    return nowMin >= startMin || nowMin <= endMin;
  }
}

/**
 * Evaluate a comparison condition.
 *
 * @param {number} value
 * @param {string} operator
 * @param {number} threshold
 * @return {boolean}
 */
function evaluate(value, operator, threshold) {
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
 * Skips users with no token stored.
 *
 * @param {string[]} userIds
 * @return {Promise<string[]>}
 */
async function getFcmTokens(userIds) {
  if (!userIds || userIds.length === 0) return [];

  const userDocs = await Promise.all(
      userIds.map((uid) => db.doc(`users/${uid}`).get()),
  );

  return userDocs
      .filter((doc) => doc.exists && doc.data().fcmToken)
      .map((doc) => doc.data().fcmToken);
}

/**
 * Firestore trigger: organisations/{orgId}/sites/{siteId}/zones/{zoneId}/sensors/{sensorId}
 */
const checkAlerts = functions.firestore
    .document(
        'organizations/{orgId}/sites/{siteId}/zones/{zoneId}/sensors/{sensorId}',
    )
    .onUpdate(async (change, context) => {
      const {orgId, siteId, zoneId, sensorId} = context.params;
      const after = change.after.data();

      if (!after || !after.fields) {
        console.log(`checkAlerts: no fields on sensor ${sensorId}, skipping`);
        return null;
      }

      // Load all alert rules for the organization
      const rulesSnap = await db
          .collection(`organizations/${orgId}/alertRules`)
          .where('enabled', '==', true)
          .get();

      if (rulesSnap.empty) {
        console.log(`checkAlerts: no enabled alert rules for org ${orgId}`);
        return null;
      }

      const now = new Date();

      for (const ruleDoc of rulesSnap.docs) {
        const rule = ruleDoc.data();

        // Time-window check
        if (!isWithinActiveWindow(now, rule.activeTimeStart, rule.activeTimeEnd)) {
          console.log(
              `checkAlerts: rule "${rule.name}" outside active window, skipping`,
          );
          continue;
        }

        // Check if the updated sensor has the watched field
        const fieldData = after.fields[rule.fieldAlias];
        if (!fieldData || fieldData.currentValue === undefined || fieldData.currentValue === null) {
          continue;
        }

        const value = Number(fieldData.currentValue);
        if (Number.isNaN(value)) continue;

        if (!evaluate(value, rule.operator, rule.threshold)) continue;

        // Condition met – send notifications
        const tokens = await getFcmTokens(rule.notifyUserIds || []);
        if (tokens.length === 0) {
          console.log(
              `checkAlerts: rule "${rule.name}" triggered but no FCM tokens found`,
          );
          continue;
        }

        const unit = fieldData.unit || '';
        const operatorLabel = {
          gt: '>', lt: '<', gte: '≥', lte: '≤', eq: '=',
        }[rule.operator] || rule.operator;

        const message = {
          notification: {
            title: `Alert: ${rule.name}`,
            body:
              `${rule.fieldAlias} ${operatorLabel} ${rule.threshold}${unit} ` +
              `(current: ${value}${unit}) ` +
              `on sensor ${sensorId} [${orgId}/${siteId}/${zoneId}]`,
          },
          data: {
            orgId,
            siteId,
            zoneId,
            sensorId,
            fieldAlias: rule.fieldAlias,
            value: String(value),
            ruleId: ruleDoc.id,
          },
          tokens,
        };

        try {
          const response = await messaging.sendEachForMulticast(message);
          console.log(
              `checkAlerts: sent ${response.successCount} notifications` +
              ` for rule "${rule.name}"`,
              {failureCount: response.failureCount},
          );

          // Remove tokens that are no longer valid
          if (response.failureCount > 0) {
            const invalidTokenUserIds = [];
            response.responses.forEach((resp, idx) => {
              if (!resp.success) {
                const errCode = resp.error && resp.error.code;
                if (
                  errCode === 'messaging/invalid-registration-token' ||
                  errCode === 'messaging/registration-token-not-registered'
                ) {
                  // Find the userId for this token and clear it
                  const badToken = tokens[idx];
                  invalidTokenUserIds.push(badToken);
                }
              }
            });

            if (invalidTokenUserIds.length > 0) {
              // Clear invalid tokens from user documents
              const userDocs = await Promise.all(
                  (rule.notifyUserIds || []).map((uid) => db.doc(`users/${uid}`).get()),
              );
              const clearOps = [];
              for (const userDoc of userDocs) {
                if (!userDoc.exists) continue;
                const data = userDoc.data();
                if (data.fcmToken && invalidTokenUserIds.includes(data.fcmToken)) {
                  clearOps.push(
                      userDoc.ref.update({fcmToken: null}),
                  );
                }
              }
              await Promise.all(clearOps);
              console.log(
                  `checkAlerts: cleared ${clearOps.length} invalid FCM token(s)`,
              );
            }
          }
        } catch (err) {
          console.error(
              `checkAlerts: failed to send notifications for rule "${rule.name}":`,
              err.message,
          );
        }
      }

      return null;
    });

module.exports = {checkAlerts};
