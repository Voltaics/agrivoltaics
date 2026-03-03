/**
 * Alert helper utilities for FCM push-notification alert evaluation.
 *
 * These functions are called from ingestSensorData after a successful
 * BigQuery insert to check alert rules and dispatch FCM notifications.
 */

const {db, messaging, bigquery, DATASET_ID, ALERTS_TABLE_ID} = require('./firebase');
const {FieldValue} = require('firebase-admin/firestore');

/**
 * Parse a 'MM/dd' date string into {month, day} (1-indexed).
 *
 * @param {string} str
 * @return {{month: number, day: number}}
 */
function parseMmDd(str) {
  const parts = str.split('/');
  return {month: parseInt(parts[0], 10), day: parseInt(parts[1], 10)};
}

/**
 * Returns true when today (UTC) falls within the [start, end] MM/dd window.
 * Handles year wrap-around (e.g. "11/01" → "03/15" spans Jan 1).
 * Null on either side means no restriction.
 *
 * @param {Date}        now
 * @param {string|null} start 'MM/dd'
 * @param {string|null} end   'MM/dd'
 * @return {boolean}
 */
function isWithinActiveDateRange(now, start, end) {
  if (!start || !end) return true;

  const s = parseMmDd(start);
  const e = parseMmDd(end);

  // Encode as month*100+day for simple integer comparison
  const nowVal = (now.getUTCMonth() + 1) * 100 + now.getUTCDate();
  const startVal = s.month * 100 + s.day;
  const endVal = e.month * 100 + e.day;

  if (startVal <= endVal) {
    // Normal range e.g. 03/15 – 09/30
    return nowVal >= startVal && nowVal <= endVal;
  }
  // Wrap-around range e.g. 11/01 – 03/15 (spans year boundary)
  return nowVal >= startVal || nowVal <= endVal;
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
 * Fetch FCM {uid, token} pairs for a list of user IDs.
 * Each user may have multiple tokens stored in the fcmTokens array.
 *
 * @param {string[]} userIds
 * @return {Promise<Array<{uid: string, token: string}>>}
 */
async function getFcmTokenPairs(userIds) {
  if (!userIds || userIds.length === 0) return [];

  const userDocs = await Promise.all(
      userIds.map((uid) => db.doc(`users/${uid}`).get()),
  );

  const pairs = [];
  for (const doc of userDocs) {
    if (!doc.exists) continue;
    const tokens = doc.data().fcmTokens;
    if (!Array.isArray(tokens)) continue;
    for (const token of tokens) {
      if (token) pairs.push({uid: doc.id, token});
    }
  }
  return pairs;
}

/**
 * Write a single in-app notification document to the notifications collection.
 *
 * @param {Object} args
 * @return {Promise<void>}
 */
async function writeInAppNotification({
  userId, organizationId, title, body, type, referenceId, expiresAt,
}) {
  const ref = db.collection('notifications').doc();
  await ref.set({
    userId,
    organizationId,
    title,
    body,
    type: type || 'alert',
    referenceType: 'alert',
    referenceId: referenceId || null,
    isRead: false,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt: expiresAt || null,
  });
}

/**
 * Fire all notifications for a triggered alert rule.
 * Shared by both runAlertChecks (production) and sendTestAlert (manual test).
 *
 * In test mode:
 *  - Title is prefixed with "[TEST]"
 *  - No `alerts` document is written
 *  - `lastFiredAt` is NOT updated (cooldown not consumed)
 *  - Bad-token pruning is skipped
 *
 * @param {Object} args
 * @param {FirebaseFirestore.DocumentSnapshot} args.ruleDoc
 * @param {Object}  args.rule            - ruleDoc.data()
 * @param {string}  args.organizationId
 * @param {string}  args.siteId
 * @param {string}  args.zoneId
 * @param {Object}  args.fieldEntry      - {value, unit, sensorId, timestamp}
 * @param {Date}    args.now
 * @param {boolean} [args.isTest=false]
 * @return {Promise<{notified: number}>}
 */
async function dispatchAlertNotifications({
  ruleDoc, rule, organizationId, siteId, zoneId, fieldEntry, now, isTest = false,
}) {
  const prefix = isTest ? '[TEST] ' : '';
  const operatorLabel =
      {gt: '>', lt: '<', gte: '\u2265', lte: '\u2264', eq: '='}[rule.operator] ||
      rule.operator;
  const alertTitle = `${prefix}Alert: ${rule.name}`;
  const alertBody =
      `${rule.fieldAlias} is ${fieldEntry.value}${fieldEntry.unit} ` +
      `(threshold: ${operatorLabel} ${rule.threshold}${fieldEntry.unit})`;

  if (!isTest) {
    // Stamp lastFiredAt immediately to prevent race conditions on concurrent ingests
    await ruleDoc.ref.update({lastFiredAt: FieldValue.serverTimestamp()});

    // Write the alert event to BigQuery (historical log)
    await bigquery
        .dataset(DATASET_ID)
        .table(ALERTS_TABLE_ID)
        .insert([{
          triggeredAt: now.toISOString(),
          organizationId,
          siteId: siteId || null,
          zoneId: zoneId || null,
          sensorId: fieldEntry.sensorId || null,
          ruleId: ruleDoc.id,
          ruleName: rule.name,
          fieldAlias: rule.fieldAlias,
          value: fieldEntry.value,
          threshold: rule.threshold,
          operator: rule.operator,
          severity: rule.severity || 'warning',
          unit: fieldEntry.unit || null,
        }]);
  }

  // In-app notifications — only users subscribed to this rule
  const notifyIds = rule.notifyUserIds || [];
  if (rule.inAppEnabled !== false && notifyIds.length > 0) {
    const inAppExpiresHours = rule.inAppExpiresAfterHours || 24;
    const expiresAt = new Date(now.getTime() + inAppExpiresHours * 3600000);
    await Promise.all(
        notifyIds.map((userId) =>
          writeInAppNotification({
            userId,
            organizationId,
            title: alertTitle,
            body: alertBody,
            type: 'alert',
            referenceId: ruleDoc.id,
            expiresAt,
          }),
        ),
    );
  }

  // FCM push — same subscriber list
  const tokenPairs = await getFcmTokenPairs(notifyIds);
  if (tokenPairs.length === 0) {
    console.log(
        `dispatchAlertNotifications: rule "${rule.name}" triggered but no FCM tokens found`,
    );
    return {notified: notifyIds.length};
  }

  const tokens = tokenPairs.map((p) => p.token);
  const message = {
    notification: {title: alertTitle, body: alertBody},
    data: {
      organizationId,
      siteId: siteId || '',
      zoneId: zoneId || '',
      sensorId: fieldEntry.sensorId || '',
      fieldAlias: rule.fieldAlias,
      value: String(fieldEntry.value),
      ruleId: ruleDoc.id,
    },
    tokens,
  };

  try {
    const response = await messaging.sendEachForMulticast(message);
    console.log(
        `dispatchAlertNotifications: sent ${response.successCount} notifications ` +
        `for rule "${rule.name}"`,
        {failureCount: response.failureCount, isTest},
    );

    // Prune invalidated tokens (production only)
    if (!isTest && response.failureCount > 0) {
      const pruneOps = [];
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
              pruneOps.push(
                  db.doc(`users/${pair.uid}`).update({
                    fcmTokens: FieldValue.arrayRemove(badToken),
                  }),
              );
              const systemExpiry = new Date(now.getTime() + 30 * 24 * 3600000);
              pruneOps.push(
                  writeInAppNotification({
                    userId: pair.uid,
                    organizationId,
                    title: 'Push notifications disabled',
                    body: 'Push notifications were disabled on one of your devices. ' +
                          'Re-enable them from Alert Rules.',
                    type: 'system',
                    referenceId: null,
                    expiresAt: systemExpiry,
                  }),
              );
            }
          }
        }
      });
      if (pruneOps.length > 0) {
        await Promise.all(pruneOps);
        console.log('dispatchAlertNotifications: pruned invalid FCM tokens');
      }
    }
  } catch (err) {
    console.error(
        `dispatchAlertNotifications: failed for rule "${rule.name}":`,
        err.message,
    );
  }

  return {notified: notifyIds.length};
}

/**
 * Evaluate all enabled alert rules for the organisation against the freshly
 * ingested sensor readings and send notifications where conditions are met.
 *
 * Called directly inside ingestSensorData after a successful BigQuery insert.
 *
 * @param {Object} args
 * @param {string}       args.organizationId
 * @param {string}       args.siteId
 * @param {string}       args.zoneId
 * @param {Array<Object>} args.bqRows - Rows inserted to BigQuery.
 * @param {Date}         args.now     - Reference time for checks.
 * @return {Promise<void>}
 */
async function runAlertChecks({organizationId, siteId, zoneId, bqRows, now}) {
  const rulesSnap = await db
      .collection(`organizations/${organizationId}/alertRules`)
      .where('enabled', '==', true)
      .get();

  if (rulesSnap.empty) return;

  // Build field→latestValue map from ingested rows.
  // Prefer primary sensor; for ties use newest timestamp.
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

    // ── Seasonal date range check (MM/dd) ────────────────────────────────
    if (!isWithinActiveDateRange(now, rule.activeRangeStart, rule.activeRangeEnd)) {
      console.log(`checkAlerts: rule "${rule.name}" outside active date range, skipping`);
      continue;
    }

    // ── Scope check ───────────────────────────────────────────────────────
    if (rule.siteId && rule.siteId !== siteId) continue;
    if (rule.zoneId && rule.zoneId !== zoneId) continue;

    // ── Cooldown check ────────────────────────────────────────────────────
    if (rule.cooldownMinutes && rule.lastFiredAt) {
      const lastFiredMs = rule.lastFiredAt.toMillis ?
          rule.lastFiredAt.toMillis() :
          Number(rule.lastFiredAt);
      const cooldownMs = rule.cooldownMinutes * 60 * 1000;
      if (now.getTime() - lastFiredMs < cooldownMs) {
        console.log(`checkAlerts: rule "${rule.name}" on cooldown, skipping`);
        continue;
      }
    }

    const fieldEntry = fieldValueMap[rule.fieldAlias];
    if (!fieldEntry) continue;

    if (!evaluateAlertCondition(fieldEntry.value, rule.operator, rule.threshold)) continue;

    // ── Rule triggered — delegate to shared dispatcher ───────────────────
    await dispatchAlertNotifications({
      ruleDoc,
      rule,
      organizationId,
      siteId,
      zoneId,
      fieldEntry,
      now,
      isTest: false,
    });
  }
}

module.exports = {runAlertChecks, dispatchAlertNotifications};
