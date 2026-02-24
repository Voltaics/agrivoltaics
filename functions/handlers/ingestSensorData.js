const functions = require('firebase-functions');
const {Timestamp} = require('firebase-admin/firestore');
const {db, bigquery, DATASET_ID, TABLE_ID} = require('../lib/firebase');

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
