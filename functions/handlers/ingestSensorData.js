const functions = require('firebase-functions');
const {Timestamp} = require('firebase-admin/firestore');
const {db, bigquery, DATASET_ID, TABLE_ID, messaging} = require('../lib/firebase');

const {CloudTasksClient} = require('@google-cloud/tasks');
const crypto = require('crypto');

const tasksClient = new CloudTasksClient();

const PROJECT_ID = 'agrivoltaics-flutter-firebase';
const TASKS_LOCATION = 'us-central1';
const TASKS_QUEUE = 'frost-trigger-queue';
const FROST_JOB_NAME = 'frost-predictor';

// Service account Cloud Tasks uses to mint oauth token
const TASKS_CALLER_SA =
  'frost-tasks-caller@agrivoltaics-flutter-firebase.iam.gserviceaccount.com';

/**
 * Creates a deterministic hash based on zoneId, newest timestamp, and row count.
 * Used as INGEST_ID to avoid duplicate training under retries/duplicates.
 *
 * @param {Object} args - Arguments.
 * @param {string} args.zoneId - Zone ID.
 * @param {string} args.newestIsoTimestamp - Newest ISO timestamp among rows.
 * @param {number} args.rowCount - Total number of inserted rows.
 * @return {string} Deterministic ingest ID.
 */
function computeIngestId({zoneId, newestIsoTimestamp, rowCount}) {
  const raw = `${zoneId}|${newestIsoTimestamp}|${rowCount}`;
  return crypto.createHash('sha256').update(raw).digest('hex');
}

/**
 * Acquire a per-zone lease lock to prevent overlapping frost predictor runs.
 * Uses a Firestore transaction to ensure atomicity across concurrent ingests.
 *
 * @param {Object} args - Arguments.
 * @param {string} args.organizationId - Organization ID.
 * @param {string} args.siteId - Site ID.
 * @param {string} args.zoneId - Zone ID.
 * @param {number} args.leaseMs - Lease duration in milliseconds.
 * @return {Promise<Object>} An object with keys:
 *    - acquired {boolean}
 *    - lockExpiresAtIso {string|null}
 */
async function acquireZoneRunLease({organizationId, siteId, zoneId, leaseMs}) {
  const lockDocPath =
    `organizations/${organizationId}/sites/${siteId}/zones/${zoneId}/frostRunLock/lease`;

  const lockRef = db.doc(lockDocPath);
  const nowMs = Date.now();
  const newExpiresMs = nowMs + leaseMs;

  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(lockRef);
    const data = snap.exists ? snap.data() : {};

    const expiresAt = data && data.expiresAt ? toDateMaybe(data.expiresAt) : null;
    const expiresMs = expiresAt ? expiresAt.getTime() : 0;

    if (expiresMs && expiresMs > nowMs) {
      // lock still active
      return {acquired: false, lockExpiresAtIso: expiresAt.toISOString()};
    }

    tx.set(
        lockRef,
        {
          expiresAt: Timestamp.fromMillis(newExpiresMs),
          updatedAt: Timestamp.now(),
        },
        {merge: true},
    );

    return {acquired: true, lockExpiresAtIso: new Date(newExpiresMs).toISOString()};
  });

  return result;
}

/**
 * Accepts Firestore Timestamps, Date objects, or ISO date strings.
 *
 * @param {*} v - Value to parse.
 * @return {Date|null} Parsed Date or null if invalid.
 */
function toDateMaybe(v) {
  if (!v) return null;
  if (typeof v.toDate === 'function') return v.toDate(); // Firestore Timestamp
  if (v instanceof Date) return v;
  const d = new Date(v); // ISO string or other date-like
  return isNaN(d.getTime()) ? null : d;
}

/**
 * Extract frost prediction settings from zone doc.
 * Supports both:
 *   zoneData.frostSettings.{...}
 * and legacy:
 *   zoneData.{...}
 *
 * @param {Object} zoneData - Zone document data.
 * @return {Object} Parsed settings.
 */
function parseFrostSettings(zoneData) {
  const src = zoneData && zoneData.frostSettings ? zoneData.frostSettings : zoneData || {};

  const enabled = typeof src.enabled === 'boolean' ? src.enabled : true;
  const predStart = toDateMaybe(src.predStart);
  const predEnd = toDateMaybe(src.predEnd);

  let tempThresholdF = null;

  if (typeof src.tempThresholdF === 'number') {
    tempThresholdF = src.tempThresholdF;
  } else if (typeof src.frostTempThreshold === 'number') {
    tempThresholdF = src.frostTempThreshold;
  }

  return {enabled, predStart, predEnd, tempThresholdF};
}

/**
 * Checks if the current time is within the configured prediction window.
 *
 * @param {Date} now - Current time.
 * @param {Date|null} predStart - Window start time.
 * @param {Date|null} predEnd - Window end time.
 * @return {boolean} True if within window.
 */
function isWithinWindow(now, predStart, predEnd) {
  if (predStart && now < predStart) return false;
  if (predEnd && now > predEnd) return false;
  return true;
}

/**
 * Determines whether the frost prediction job should be triggered.
 *
 * @param {Object} args - Arguments.
 * @param {Date} args.now - Current timestamp (usually newest reading time).
 * @param {number|null} args.tempF - Current temperature in °F.
 * @param {Object} args.settings - Parsed frost settings.
 * @return {{ok: boolean, reason: string}} Decision object.
 */
function shouldTriggerFrostJob({now, tempF, settings}) {
  if (!settings.enabled) return {ok: false, reason: 'disabled'};
  if (!isWithinWindow(now, settings.predStart, settings.predEnd)) {
    return {ok: false, reason: 'outside_prediction_window'};
  }
  if (typeof settings.tempThresholdF !== 'number') {
    return {ok: false, reason: 'missing_temp_threshold'};
  }
  if (typeof tempF !== 'number' || Number.isNaN(tempF)) {
    return {ok: false, reason: 'missing_temperature'};
  }

  if (tempF > settings.tempThresholdF) {
    return {ok: false, reason: 'temperature_not_low_enough'};
  }
  return {ok: true, reason: 'ok'};
}

/**
 * Pull current temperature from what we just inserted.
 * Prefers primary sensors when available.
 *
 * @param {Array<Object>} allBqRows - Rows inserted into BigQuery.
 * @return {number|null} Latest temperature (°F) if available, else null.
 */
function extractCurrentTempF(allBqRows) {
  const tempRows = allBqRows.filter((r) => r.field === 'temperature');
  if (tempRows.length === 0) return null;

  const primary = tempRows.filter((r) => r.primarySensor === true);
  const candidates = primary.length > 0 ? primary : tempRows;

  let newest = candidates[0];
  for (const r of candidates) {
    if (r.timestamp > newest.timestamp) newest = r;
  }

  const v = newest.value;
  return typeof v === 'number' ? v : v != null ? Number(v) : null;
}

/**
 * Enqueue a Cloud Task that calls the Cloud Run Jobs "run" API.
 * Includes per-execution env overrides (ZONE_ID and INGEST_ID).
 *
 * @param {Object} args - Arguments.
 * @param {string} args.zoneId - Zone ID.
 * @param {string} args.ingestId - Deterministic ingest ID.
 * @return {Promise<string>} Created task name.
 */
async function enqueueFrostJobRun({zoneId, ingestId}) {
  const parent = tasksClient.queuePath(PROJECT_ID, TASKS_LOCATION, TASKS_QUEUE);
  const url =
    `https://run.googleapis.com/v2/projects/${PROJECT_ID}` +
    `/locations/${TASKS_LOCATION}` +
    `/jobs/${FROST_JOB_NAME}:run`;

  const payload = {
    overrides: {
      containerOverrides: [
        {
          env: [
            {name: 'ZONE_ID', value: zoneId},
            {name: 'INGEST_ID', value: ingestId},
          ],
        },
      ],
    },
  };

  const task = {
    httpRequest: {
      httpMethod: 'POST',
      url,
      headers: {'Content-Type': 'application/json'},
      body: Buffer.from(JSON.stringify(payload)).toString('base64'),
      oauthToken: {
        serviceAccountEmail: TASKS_CALLER_SA,
        scope: 'https://www.googleapis.com/auth/cloud-platform',
      },
    },
  };

  const [resp] = await tasksClient.createTask({parent, task});
  return resp.name;
}

// ─── Alert helpers ────────────────────────────────────────────────────────────

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
 * This is called directly inside ingestSensorData after BigQuery insert so
 * that alert evaluation happens in the same invocation rather than via a
 * separate Firestore-triggered function.
 *
 * @param {Object} args
 * @param {string} args.organizationId
 * @param {string} args.siteId
 * @param {string} args.zoneId
 * @param {Array<Object>} args.bqRows  - Rows that were inserted to BigQuery.
 * @param {Date}   args.now            - Reference time for active-window check.
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

// ─── HTTPS Cloud Function: Ingest Sensor Data ────────────────────────────────

/**
 * HTTPS Cloud Function: Ingest Sensor Data
 *
 * Receives sensor data from devices via HTTPS POST request.
 * Supports batch ingestion of multiple sensors in a single request.
 *
 * Expected payload format:
 * {
 *   "organizationId": "org1",
 *   "siteId": "site1",
 *   "zoneId": "zone1",
 *   "sensors": [
 *     {
 *       "sensorId": "sensor1",
 *       "timestamp": 1700000000,
 *       "readings": {
 *         "temperature": { "value": 72.5, "unit": "°F" },
 *         "humidity": { "value": 65.2, "unit": "%" }
 *       }
 *     }
 *   ]
 * }
 *
 * @param {Object} req - Express request object
 * @param {Object} res - Express response object
 * @returns {Promise<void>} JSON response with success status
 */
const ingestSensorData = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(204).send('');
  }

  if (req.method !== 'POST') {
    return res.status(405).json({
      success: false,
      error: 'Method Not Allowed. Use POST.',
    });
  }

  try {
    const {organizationId, siteId, zoneId, sensors} = req.body;

    if (!organizationId) {
      return res.status(400).json({
        success: false,
        error: 'Missing required field: organizationId',
      });
    }

    if (!siteId) {
      return res.status(400).json({
        success: false,
        error: 'Missing required field: siteId',
      });
    }

    if (!zoneId) {
      return res.status(400).json({
        success: false,
        error: 'Missing required field: zoneId',
      });
    }

    if (!sensors || !Array.isArray(sensors) || sensors.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'Missing or invalid sensors array (must be non-empty array)',
      });
    }

    // Read zone doc once, parse frost settings once
    const zoneDocPath = `organizations/${organizationId}/sites/${siteId}/zones/${zoneId}`;
    const zoneDoc = await db.doc(zoneDocPath).get();
    const zoneData = zoneDoc.exists ? zoneDoc.data() : {};
    const frostSettings = parseFrostSettings(zoneData);

    const allBqRows = [];
    const processedSensors = [];
    const errors = [];

    const readingsSnapshot = await db.collection('readings').get();
    const validReadingAliases = new Set(readingsSnapshot.docs.map((doc) => doc.id));

    for (let i = 0; i < sensors.length; i++) {
      const sensor = sensors[i];
      const {sensorId, timestamp, readings} = sensor;

      try {
        if (!sensorId) {
          errors.push({index: i, error: 'Missing sensorId'});
          continue;
        }

        if (!timestamp || typeof timestamp !== 'number') {
          errors.push({
            index: i,
            sensorId,
            error: 'Missing or invalid timestamp (must be Unix timestamp in seconds)',
          });
          continue;
        }

        if (!readings || typeof readings !== 'object' || Object.keys(readings).length === 0) {
          errors.push({index: i, sensorId, error: 'Missing or invalid readings object'});
          continue;
        }

        let hasInvalidReading = false;
        for (const [fieldName, reading] of Object.entries(readings)) {
          if (reading.value === null || reading.value === undefined) {
            errors.push({
              index: i,
              sensorId,
              error: `Reading '${fieldName}' is missing value`,
            });
            hasInvalidReading = true;
            break;
          }
          if (!reading.unit) {
            errors.push({
              index: i,
              sensorId,
              error: `Reading '${fieldName}' is missing unit`,
            });
            hasInvalidReading = true;
            break;
          }

          if (!validReadingAliases.has(fieldName)) {
            console.warn(
                `Warning: Reading alias '${fieldName}' not found in readings collection. ` +
                `Sensor ${sensorId} may have unrecognized field.`,
            );
          }
        }

        if (hasInvalidReading) {
          continue;
        }

        const timestampObj = Timestamp.fromMillis(timestamp * 1000);

        const sensorDocPath =
          `organizations/${organizationId}/sites/${siteId}/zones/${zoneId}/sensors/${sensorId}`;
        const sensorDoc = await db.doc(sensorDocPath).get();

        if (!sensorDoc.exists) {
          errors.push({
            index: i,
            sensorId,
            error: `Sensor not found at path: ${sensorDocPath}`,
          });
          continue;
        }

        const sensorData = sensorDoc.data();

        const fieldUpdates = {};
        for (const [fieldName, reading] of Object.entries(readings)) {
          fieldUpdates[`fields.${fieldName}.currentValue`] = reading.value;
          fieldUpdates[`fields.${fieldName}.unit`] = reading.unit;
          fieldUpdates[`fields.${fieldName}.lastUpdated`] = timestampObj;
        }

        await db.doc(sensorDocPath).update({
          ...fieldUpdates,
          lastReading: timestampObj,
        });

        const date = new Date(timestamp * 1000);
        const isoTimestamp = date.toISOString();

        const sensorBqRows = Object.entries(readings).map(([field, reading]) => {
          const zoneReadings = zoneData.readings || {};
          const isPrimaryForField = zoneReadings[field] === sensorId;
          return {
            timestamp: isoTimestamp,
            organizationId,
            siteId,
            zoneId,
            sensorId,
            sensorModel: sensorData.model || 'Unknown',
            sensorName: sensorData.name || 'Unnamed',
            field,
            value: reading.value,
            unit: reading.unit,
            primarySensor: isPrimaryForField,
          };
        });

        allBqRows.push(...sensorBqRows);
        processedSensors.push({
          sensorId,
          fieldsUpdated: Object.keys(readings),
          timestamp: isoTimestamp,
        });
      } catch (sensorError) {
        console.error(`Error processing sensor ${sensorId}:`, sensorError);
        errors.push({
          index: i,
          sensorId: sensorId || 'unknown',
          error: sensorError.message || 'Unknown error',
        });
      }
    }

    if (allBqRows.length > 0) {
      try {
        await bigquery
            .dataset(DATASET_ID)
            .table(TABLE_ID)
            .insert(allBqRows, {skipInvalidRows: false, ignoreUnknownValues: false});

        console.log(
            `Inserted ${allBqRows.length} rows to BigQuery ` +
            `for ${processedSensors.length} sensors`,
        );

        // Compute ingestId + decide whether to trigger frost job
        const newestIsoTimestamp = allBqRows.reduce(
            (maxTs, r) => (r.timestamp > maxTs ? r.timestamp : maxTs),
            '',
        );

        const ingestId = computeIngestId({
          zoneId,
          newestIsoTimestamp,
          rowCount: allBqRows.length,
        });

        // Use newest data time as "now" for the window check
        const now = new Date(newestIsoTimestamp);
        const currentTempF = extractCurrentTempF(allBqRows);

        const decision = shouldTriggerFrostJob({
          now,
          tempF: currentTempF,
          settings: frostSettings,
        });

        if (!decision.ok) {
          let predStartLog = frostSettings.predStart;
          if (predStartLog && typeof predStartLog.toISOString === 'function') {
            predStartLog = predStartLog.toISOString();
          }

          let predEndLog = frostSettings.predEnd;
          if (predEndLog && typeof predEndLog.toISOString === 'function') {
            predEndLog = predEndLog.toISOString();
          }

          console.log('Not triggering frost job:', {
            zoneId: zoneId,
            ingestId: ingestId,
            reason: decision.reason,
            currentTempF: currentTempF,
            predStart: predStartLog,
            predEnd: predEndLog,
            tempThresholdF: frostSettings.tempThresholdF,
          });
        } else {
          try {
            // Prevent overlapping predictor runs per zone
            const leaseMs = 5 * 60 * 1000; // 5 minutes; adjust to worst-case job runtime + buffer
            const lease = await acquireZoneRunLease({
              organizationId,
              siteId,
              zoneId,
              leaseMs,
            });

            if (!lease.acquired) {
              console.log('Skipping frost job enqueue; zone lease active:', {
                zoneId: zoneId,
                ingestId: ingestId,
                lockExpiresAt: lease.lockExpiresAtIso,
              });
            } else {
              const taskName = await enqueueFrostJobRun({zoneId, ingestId});
              console.log('Enqueued frost job via Cloud Tasks:', {
                taskName: taskName,
                zoneId: zoneId,
                ingestId: ingestId,
                currentTempF: currentTempF,
              });
            }
          } catch (e) {
            console.error('Failed to enqueue frost job task:', e.message || e);
          }
        }

        // Run alert checks against freshly ingested readings.
        // Errors here are non-fatal and must not affect the HTTP response.
        try {
          await runAlertChecks({
            organizationId,
            siteId,
            zoneId,
            bqRows: allBqRows,
            now,
          });
        } catch (alertErr) {
          console.error('Alert check error:', alertErr.message || alertErr);
        }
      } catch (bqError) {
        console.error('BigQuery insert error:', bqError.message);
        if (bqError.errors && Array.isArray(bqError.errors)) {
          console.error('Detailed insert errors:');
          bqError.errors.forEach((err, index) => {
            console.error(`  Error ${index}:`, JSON.stringify(err, null, 2));
          });
        }
      }
    }

    const response = {
      success: processedSensors.length > 0,
      message: `Processed ${processedSensors.length} of ${sensors.length} sensors`,
      sensorsProcessed: processedSensors.length,
      sensorsTotal: sensors.length,
      sensors: processedSensors,
    };

    if (errors.length > 0) {
      response.errors = errors;
      response.partialSuccess = processedSensors.length > 0;
    }

    const statusCode = processedSensors.length > 0 ? 200 : 400;
    return res.status(statusCode).json(response);
  } catch (error) {
    console.error('Ingestion error:', error);
    return res.status(500).json({
      success: false,
      error: error.message || 'Internal server error',
    });
  }
});

module.exports = {ingestSensorData};
