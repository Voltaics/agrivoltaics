/**
 * Alert helper utilities for FCM push-notification alert evaluation.
 *
 * These functions are called from ingestSensorData after a successful
 * BigQuery insert to check alert rules and dispatch FCM notifications.
 */

const {db, messaging, bigquery, DATASET_ID, ALERTS_TABLE_ID} = require('./firebase');
const {FieldValue} = require('firebase-admin/firestore');

/**
 * Parse a 'MM/dd' date string into {month, day}.
 * @param {string} str
 * @return {{month: number, day: number}}
 */
function parseMmDd(str) {
  const parts = str.split('/');
  return {month: parseInt(parts[0], 10), day: parseInt(parts[1], 10)};
}

/**
 * Returns true when today (UTC) falls within the [start, end] MM/dd window.
 * Handles year wrap-around.
 * @param {Date} now
 * @param {string|null} start
 * @param {string|null} end
 * @return {boolean}
 */
function isWithinActiveDateRange(now, start, end) {
  if (!start || !end) return true;

  const s = parseMmDd(start);
  const e = parseMmDd(end);

  const nowVal = (now.getUTCMonth() + 1) * 100 + now.getUTCDate();
  const startVal = s.month * 100 + s.day;
  const endVal = e.month * 100 + e.day;

  if (startVal <= endVal) {
    return nowVal >= startVal && nowVal <= endVal;
  }
  return nowVal >= startVal || nowVal <= endVal;
}

/**
 * Evaluate a comparison condition.
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
 * Convert to finite number or null.
 * @param {*} value
 * @return {number|null}
 */
function toNumberOrNull(value) {
  if (value === null || value === undefined) return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

/**
 * Build an alert summary string for a threshold rule.
 * @param {Object} rule
 * @param {Object} fieldEntry
 * @return {{title: string, body: string}}
 */
function buildThresholdAlertMessage(rule, fieldEntry) {
  const operatorLabel =
    {gt: '>', lt: '<', gte: '≥', lte: '≤', eq: '='}[rule.operator] || rule.operator;

  const title = `Alert: ${rule.name}`;
  const body =
    `${rule.fieldAlias} is ${fieldEntry.value}${fieldEntry.unit || ''} ` +
    `(threshold: ${operatorLabel} ${rule.threshold}${fieldEntry.unit || ''})`;

  return {title, body};
}

/**
 * Build an alert summary string for a frost warning rule.
 * @param {Object} rule
 * @param {Object} details
 * @return {{title: string, body: string}}
 */
function buildFrostAlertMessage(rule, details) {
  const title = `Alert: ${rule.name}`;
  const body =
    `Frost warning conditions detected: ` +
    `temp ${details.airTempF}°F, humidity ${details.humidity}%, ` +
    `soil temp ${details.soilTempF}°F, ` +
    `temp drop ${details.tempDropRateFPerHour.toFixed(1)}°F/hr` +
    (details.light != null ? `, light ${details.light}` : '');

  return {title, body};
}

/**
 * Fetch FCM {uid, token} pairs for a list of user IDs.
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
 * Write a single in-app notification document.
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
 * Query recent BigQuery readings for fields needed by frost warning.
 *
 * Expects the sensor readings table to be in dataset sensor_data and table readings.
 * If your table name differs, change `readings` below.
 *
 * @param {Object} args
 * @param {string} args.organizationId
 * @param {string} args.siteId
 * @param {string} args.zoneId
 * @param {Date} args.now
 * @return {Promise<Object>}
 */
async function fetchRecentFrostContext({organizationId, siteId, zoneId, now}) {
  const endIso = now.toISOString();
  const startIso = new Date(now.getTime() - 90 * 60 * 1000).toISOString();

  const query = `
    SELECT
      field,
      value,
      unit,
      sensorId,
      timestamp,
      primarySensor
    FROM \`${bigquery.projectId}.sensor_data.readings\`
    WHERE organizationId = @organizationId
      AND siteId = @siteId
      AND zoneId = @zoneId
      AND field IN ('temperature', 'humidity', 'soilTemperature', 'light')
      AND timestamp BETWEEN TIMESTAMP(@startIso) AND TIMESTAMP(@endIso)
    ORDER BY timestamp DESC
  `;

  const [rows] = await bigquery.query({
    query,
    params: {
      organizationId,
      siteId,
      zoneId,
      startIso,
      endIso,
    },
  });

  const latest = {};
  const oneHourAgoTargetMs = now.getTime() - 60 * 60 * 1000;
  let bestTempOneHourAgo = null;
  let bestTempDistanceMs = Number.POSITIVE_INFINITY;

  for (const row of rows) {
    const field = row.field;
    const value = toNumberOrNull(row.value);
    if (value == null) continue;

    const ts = new Date(row.timestamp.value || row.timestamp);
    const entry = {
      value,
      unit: row.unit || '',
      sensorId: row.sensorId || null,
      timestamp: ts.toISOString(),
      primarySensor: !!row.primarySensor,
    };

    if (!latest[field]) {
      latest[field] = entry;
    }

    if (field === 'temperature') {
      const distanceMs = Math.abs(ts.getTime() - oneHourAgoTargetMs);
      if (distanceMs < bestTempDistanceMs) {
        bestTempDistanceMs = distanceMs;
        bestTempOneHourAgo = entry;
      }
    }
  }

  return {
    current: {
      temperature: latest.temperature || null,
      humidity: latest.humidity || null,
      soilTemperature: latest.soilTemperature || null,
      light: latest.light || null,
    },
    oneHourAgoTemperature: bestTempOneHourAgo,
  };
}

/**
 * Evaluate a frost warning rule.
 *
 * Default thresholds come from your PDF guidance:
 * - temp drop > 2 deg_F/hour
 * - humidity >= 90%
 * - air temp in the 30s
 * - soil temp <= 45 deg_F
 * - low light as nighttime/clear-sky proxy
 *
 * @param {Object} rule
 * @param {Object} frostContext
 * @return {{matched: boolean, details: (Object|null|undefined), fieldEntry: (Object|null|undefined)}}
 */
function evaluateFrostWarning(rule, frostContext) {
  const config = rule.frostConfig || {};

  const tempDropRateThresholdRaw = toNumberOrNull(config.tempDropRateFPerHour);
  const humidityMinRaw = toNumberOrNull(config.humidityMin);
  const airTempMaxFRaw = toNumberOrNull(config.airTempMaxF);
  const soilTempMaxFRaw = toNumberOrNull(config.soilTempMaxF);
  const lightMaxRaw = toNumberOrNull(config.lightMax);

  const tempDropRateThreshold =
    tempDropRateThresholdRaw != null ? tempDropRateThresholdRaw : 2.0;
  const humidityMin =
    humidityMinRaw != null ? humidityMinRaw : 90.0;
  const airTempMaxF =
    airTempMaxFRaw != null ? airTempMaxFRaw : 39.0;
  const soilTempMaxF =
    soilTempMaxFRaw != null ? soilTempMaxFRaw : 45.0;
  const lightMax =
    lightMaxRaw != null ? lightMaxRaw : 5000.0;
  const requireLowLight = config.requireLowLight !== false;

  const air = frostContext.current.temperature;
  const humidity = frostContext.current.humidity;
  const soil = frostContext.current.soilTemperature;
  const light = frostContext.current.light;
  const oneHourAgoAir = frostContext.oneHourAgoTemperature;

  if (!air || !humidity || !soil || !oneHourAgoAir) {
    return {
      matched: false,
      reason: 'missing_required_context',
      missing: {
        air: !air,
        humidity: !humidity,
        soil: !soil,
        oneHourAgoAir: !oneHourAgoAir,
      },
    };
  }

  const airTempF = toNumberOrNull(air.value);
  const humidityPct = toNumberOrNull(humidity.value);
  const soilTempF = toNumberOrNull(soil.value);
  const lightValue = light ? toNumberOrNull(light.value) : null;
  const oneHourAgoTempF = toNumberOrNull(oneHourAgoAir.value);

  if (
    airTempF == null ||
    humidityPct == null ||
    soilTempF == null ||
    oneHourAgoTempF == null
  ) {
    return {
      matched: false,
      reason: 'invalid_numeric_context',
    };
  }

  const tempDropRateFPerHour = oneHourAgoTempF - airTempF;

  if (tempDropRateFPerHour <= tempDropRateThreshold) return {matched: false};
  if (humidityPct < humidityMin) return {matched: false};
  if (airTempF > airTempMaxF) return {matched: false};
  if (soilTempF > soilTempMaxF) return {matched: false};
  if (requireLowLight && (lightValue == null || lightValue > lightMax)) return {matched: false};

  const details = {
    airTempF,
    humidity: humidityPct,
    soilTempF,
    light: lightValue,
    tempDropRateFPerHour,
  };

  // Reuse a fieldEntry-shaped object so dispatch can still attach a sensor/timestamp.
  const fieldEntry = {
    value: airTempF,
    unit: air.unit || '°F',
    sensorId: air.sensorId || '',
    timestamp: air.timestamp,
    primarySensor: air.primarySensor || false,
  };

  return {matched: true, details, fieldEntry};
}

/**
 * Fire notifications for a triggered alert rule.
 *
 * @param {Object} args
 * @param {FirebaseFirestore.DocumentSnapshot} args.ruleDoc
 * @param {Object} args.rule
 * @param {string} args.organizationId
 * @param {string} args.siteId
 * @param {string} args.zoneId
 * @param {Object} args.fieldEntry
 * @param {Date} args.now
 * @param {boolean} [args.isTest=false]
 * @param {Object|null} [args.ruleMatchDetails=null]
 * @return {Promise<{notified: number}>}
 */
async function dispatchAlertNotifications({
  ruleDoc,
  rule,
  organizationId,
  siteId,
  zoneId,
  fieldEntry,
  now,
  isTest = false,
  ruleMatchDetails = null,
}) {
  const prefix = isTest ? '[TEST] ' : '';

  let messageParts;
  if (rule.ruleType === 'frost_warning') {
    messageParts = buildFrostAlertMessage(rule, ruleMatchDetails || {});
  } else {
    messageParts = buildThresholdAlertMessage(rule, fieldEntry);
  }

  const alertTitle = `${prefix}${messageParts.title}`;
  const alertBody = messageParts.body;

  if (!isTest) {
    await ruleDoc.ref.update({lastFiredAt: FieldValue.serverTimestamp()});

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
          ruleType: rule.ruleType || 'threshold',
          fieldAlias: rule.fieldAlias || null,
          value: fieldEntry.value,
          threshold: rule.threshold != null ? rule.threshold : null,
          operator: rule.operator != null ? rule.operator : null,
          severity: rule.severity || 'warning',
          unit: fieldEntry.unit || null,
          metadata: ruleMatchDetails ? JSON.stringify(ruleMatchDetails) : null,
        }]);
  }

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
      fieldAlias: rule.fieldAlias || '',
      value: String(fieldEntry.value != null ? fieldEntry.value : ''),
      ruleId: ruleDoc.id,
      ruleType: rule.ruleType || 'threshold',
    },
    tokens,
  };

  try {
    const response = await messaging.sendEachForMulticast(message);
    console.log(
        `dispatchAlertNotifications: sent ${response.successCount} notifications for rule "${rule.name}"`,
        {failureCount: response.failureCount, isTest},
    );

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
                    body: 'Push notifications were disabled on one of your devices. Re-enable them from Alert Rules.',
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
 * @param {Object} args
 * @param {string} args.organizationId
 * @param {string} args.siteId
 * @param {string} args.zoneId
 * @param {Array<Object>} args.bqRows
 * @param {Date} args.now
 * @return {Promise<void>}
 */
async function runAlertChecks({organizationId, siteId, zoneId, bqRows, now}) {
  const rulesSnap = await db
      .collection(`organizations/${organizationId}/alertRules`)
      .where('enabled', '==', true)
      .get();

  if (rulesSnap.empty) return;

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

  // Only fetch frost context if at least one enabled frost rule exists.
  const hasFrostRules = rulesSnap.docs.some(
      (doc) => (doc.data().ruleType || 'threshold') === 'frost_warning',
  );

  let frostContext = null;
  if (hasFrostRules) {
    try {
      frostContext = await fetchRecentFrostContext({
        organizationId,
        siteId,
        zoneId,
        now,
      });
    } catch (err) {
      console.error('runAlertChecks: failed to fetch frost context:', err.message);
    }
  }

  for (const ruleDoc of rulesSnap.docs) {
    const rule = ruleDoc.data();
    const ruleType = rule.ruleType || 'threshold';

    if (!isWithinActiveDateRange(now, rule.activeRangeStart, rule.activeRangeEnd)) {
      console.log(`checkAlerts: rule "${rule.name}" outside active date range, skipping`);
      continue;
    }

    if (rule.siteId && rule.siteId !== siteId) continue;
    if (rule.zoneId && rule.zoneId !== zoneId) continue;

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

    if (ruleType === 'frost_warning') {
      if (!frostContext) continue;

      const result = evaluateFrostWarning(rule, frostContext);
      if (!result.matched) continue;

      await dispatchAlertNotifications({
        ruleDoc,
        rule,
        organizationId,
        siteId,
        zoneId,
        fieldEntry: result.fieldEntry,
        now,
        isTest: false,
        ruleMatchDetails: result.details,
      });
      continue;
    }

    const fieldEntry = fieldValueMap[rule.fieldAlias];
    if (!fieldEntry) continue;

    if (!evaluateAlertCondition(fieldEntry.value, rule.operator, rule.threshold)) {
      continue;
    }

    await dispatchAlertNotifications({
      ruleDoc,
      rule,
      organizationId,
      siteId,
      zoneId,
      fieldEntry,
      now,
      isTest: false,
      ruleMatchDetails: null,
    });
  }
}

module.exports = {
  runAlertChecks,
  dispatchAlertNotifications,
  evaluateFrostWarning,
  fetchRecentFrostContext,
};
