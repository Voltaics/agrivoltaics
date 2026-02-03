/**
 * Firebase Cloud Functions for Agrivoltaics Sensor Data Ingestion
 *
 * This module provides serverless functions for managing sensor data:
 *
 * Functions:
 * - ingestSensorData: HTTPS endpoint for receiving sensor data from Arduino devices
 * - syncSensorLookup: Firestore trigger to maintain the sensorLookup collection
 * - setupBigQuery: One-time setup to create BigQuery dataset and table
 * - checkSensorStatus: Scheduled task to mark offline sensors
 *
 * Storage Architecture:
 * - Firestore: Stores current sensor states and metadata
 * - BigQuery: Stores historical time-series data for analytics
 */

const admin = require('firebase-admin');
const functions = require('firebase-functions');
const {BigQuery} = require('@google-cloud/bigquery');
const {Timestamp} = require('firebase-admin/firestore');

// Initialize Firebase Admin SDK
admin.initializeApp();
const db = admin.firestore();
const bigquery = new BigQuery();

// BigQuery configuration
const DATASET_ID = 'sensor_data';
const TABLE_ID = 'readings';

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
 *     },
 *     {
 *       "sensorId": "sensor2",
 *       "timestamp": 1700000000,
 *       "readings": {
 *         "light": { "value": 45000, "unit": "lux" }
 *       }
 *     }
 *   ]
 * }
 *
 * Process:
 * 1. Validate request payload
 * 2. For each sensor:
 *    a. Construct sensor document path from IDs
 *    b. Verify sensor exists and is active
 *    c. Update sensor fields in Firestore (current values)
 *    d. Collect time-series data for BigQuery
 * 3. Batch insert all sensor data into BigQuery
 *
 * @param {Object} req - Express request object
 * @param {Object} res - Express response object
 * @returns {Promise<void>} JSON response with success status
 */
exports.ingestSensorData = functions.https.onRequest(async (req, res) => {
  // CORS headers - allow all origins (adjust in production for security)
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  // Handle preflight OPTIONS request
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

    // Validate required ID fields
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

    // Validate sensors array
    if (!sensors || !Array.isArray(sensors) || sensors.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'Missing or invalid sensors array (must be non-empty array)',
      });
    }

    const allBqRows = [];
    const processedSensors = [];
    const errors = [];

    // Pre-load all valid reading aliases once
    const readingsSnapshot = await db.collection('readings').get();
    const validReadingAliases = new Set(readingsSnapshot.docs.map((doc) => doc.id));

    // Process each sensor
    for (let i = 0; i < sensors.length; i++) {
      const sensor = sensors[i];
      const {sensorId, timestamp, readings} = sensor;

      try {
        // Validate sensor data
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

        // Validate each reading has value and unit
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

          // Warn if reading alias not found in readings collection
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

        // Construct sensor document path and verify sensor exists
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

        // Check if this sensor is a primary sensor for the zone
        const zoneDocPath = `organizations/${organizationId}/sites/${siteId}/zones/${zoneId}`;
        const zoneDoc = await db.doc(zoneDocPath).get();
        const zoneData = zoneDoc.exists ? zoneDoc.data() : {};

        // Check if sensor is active
        if (sensorData.status !== 'active') {
          errors.push({
            index: i,
            sensorId,
            error: `Sensor is inactive. Status: ${sensorData.status || 'unknown'}`,
          });
          continue;
        }

        // Update sensor fields in Firestore
        const fieldUpdates = {};
        for (const [fieldName, reading] of Object.entries(readings)) {
          fieldUpdates[`fields.${fieldName}.currentValue`] = reading.value;
          fieldUpdates[`fields.${fieldName}.unit`] = reading.unit;
          fieldUpdates[`fields.${fieldName}.lastUpdated`] = timestampObj;
        }

        await db.doc(sensorDocPath).update({
          ...fieldUpdates,
          lastReading: timestampObj,
          isOnline: true,
        });

        // Build BigQuery rows for this sensor
        const date = new Date(timestamp * 1000);
        const isoTimestamp = date.toISOString();

        const sensorBqRows = Object.entries(readings).map(([field, reading]) => {
          // Check if this sensor is the primary for this specific field
          const zoneReadings = zoneData.readings || {};
          const isPrimaryForField = zoneReadings[field] === sensorId;
          return {
            timestamp: isoTimestamp,
            organizationId: organizationId,
            siteId: siteId,
            zoneId: zoneId,
            sensorId: sensorId,
            sensorModel: sensorData.model || 'Unknown',
            sensorName: sensorData.name || 'Unnamed',
            field: field,
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

    // Insert all BigQuery rows in a single batch
    if (allBqRows.length > 0) {
      try {
        await bigquery
            .dataset(DATASET_ID)
            .table(TABLE_ID)
            .insert(allBqRows, {skipInvalidRows: false, ignoreUnknownValues: false});

        console.log(`Inserted ${allBqRows.length} rows to BigQuery ` +
          `for ${processedSensors.length} sensors`);
      } catch (bqError) {
        console.error('BigQuery insert error:', bqError.message);
        if (bqError.errors && Array.isArray(bqError.errors)) {
          console.error('Detailed insert errors:');
          bqError.errors.forEach((err, index) => {
            console.error(`  Error ${index}:`, JSON.stringify(err, null, 2));
          });
        }
        // Log error but don't fail the request - data is persisted in Firestore
      }
    }

    // Return response with results
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

/**
 * HTTPS Cloud Function: Setup BigQuery
 *
 * One-time setup function to create BigQuery dataset and table with optimized
 * configuration for time-series sensor data:
 * - Daily partitioning on timestamp field for efficient queries
 * - Clustering by sensorId and field for fast filtering
 *
 * Call this function once before the first data ingestion.
 *
 * @param {Object} req - Express request object
 * @param {Object} res - Express response object
 * @returns {Promise<void>} JSON response with setup status
 */
exports.setupBigQuery = functions.https.onRequest(async (req, res) => {
  try {
    // Create dataset if not exists
    const dataset = bigquery.dataset(DATASET_ID);
    const [datasetExists] = await dataset.exists();

    if (!datasetExists) {
      await bigquery.createDataset(DATASET_ID, {
        location: 'US',
        description: 'Agrivoltaics sensor data for time-series analytics',
      });
      console.log(`Created dataset: ${DATASET_ID}`);
    } else {
      console.log(`Dataset ${DATASET_ID} already exists`);
    }

    // Define expected schema
    const expectedSchema = [
      {name: 'timestamp', type: 'TIMESTAMP', mode: 'REQUIRED'},
      {name: 'organizationId', type: 'STRING', mode: 'REQUIRED'},
      {name: 'siteId', type: 'STRING', mode: 'REQUIRED'},
      {name: 'zoneId', type: 'STRING', mode: 'REQUIRED'},
      {name: 'sensorId', type: 'STRING', mode: 'REQUIRED'},
      {name: 'sensorModel', type: 'STRING', mode: 'NULLABLE'},
      {name: 'sensorName', type: 'STRING', mode: 'NULLABLE'},
      {name: 'field', type: 'STRING', mode: 'REQUIRED'},
      {name: 'value', type: 'FLOAT', mode: 'REQUIRED'},
      {name: 'unit', type: 'STRING', mode: 'REQUIRED'},
      {name: 'primarySensor', type: 'BOOLEAN', mode: 'NULLABLE'},
    ];

    // Create table with schema, partitioning, and clustering
    const table = dataset.table(TABLE_ID);
    const [tableExists] = await table.exists();

    if (!tableExists) {
      const options = {
        schema: expectedSchema,
        timePartitioning: {
          type: 'DAY',
          field: 'timestamp',
          expirationMs: null, // Keep data forever (change to auto-delete old data)
        },
        clustering: {
          fields: ['sensorId', 'field'],
        },
        description: 'Sensor readings with daily partitioning and clustering by sensor/field',
      };

      await dataset.createTable(TABLE_ID, options);
      console.log(`Created table: ${TABLE_ID} with partitioning and clustering`);

      return res.status(200).json({
        success: true,
        message: 'BigQuery setup completed',
        dataset: DATASET_ID,
        table: TABLE_ID,
        partitioning: 'DAY on timestamp field',
        clustering: 'sensorId, field',
      });
    } else {
      // Table exists - verify schema matches
      const [metadata] = await table.getMetadata();
      const currentSchema = metadata.schema.fields;

      // Compare schemas
      const schemaMatches = expectedSchema.every((expectedField) => {
        const currentField = currentSchema.find((f) => f.name === expectedField.name);
        if (!currentField) {
          console.log(`Missing field: ${expectedField.name}`);
          return false;
        }
        if (currentField.type !== expectedField.type) {
          console.log(
              `Type mismatch for ${expectedField.name}: expected ${expectedField.type}, got ${currentField.type}`);
          return false;
        }
        const currentMode = currentField.mode || 'NULLABLE';
        if (currentMode !== expectedField.mode) {
          console.log(`Mode mismatch for ${expectedField.name}: expected ${expectedField.mode}, got ${currentMode}`);
          return false;
        }
        return true;
      }) && currentSchema.length === expectedSchema.length;

      if (schemaMatches) {
        return res.status(200).json({
          success: true,
          message: 'BigQuery table already exists with correct schema',
          dataset: DATASET_ID,
          table: TABLE_ID,
          schemaValid: true,
        });
      } else {
        return res.status(400).json({
          success: false,
          message: 'BigQuery table exists but schema does not match',
          dataset: DATASET_ID,
          table: TABLE_ID,
          schemaValid: false,
          expectedSchema: expectedSchema,
          currentSchema: currentSchema,
        });
      }
    }
  } catch (error) {
    console.error('BigQuery setup error:', error);
    return res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

/**
 * Scheduled Cloud Function: Check Sensor Status
 *
 * Periodically monitors sensor health by checking for stale data.
 * Marks sensors as offline if they haven't sent data in 30 minutes.
 *
 * Schedule: Once daily
 * Timeout Threshold: 30 minutes of inactivity
 *
 * @param {Object} context - Function context
 * @returns {Promise<void>}
 */
exports.checkSensorStatus = functions.pubsub
    .schedule('every 24 hours')
    .onRun(async (context) => {
      const thirtyMinutesAgo = Timestamp.fromMillis(Date.now() - 30 * 60 * 1000);

      try {
        const lookupSnapshot = await db.collection('sensorLookup')
            .where('isActive', '==', true)
            .where('lastDataReceived', '<', thirtyMinutesAgo)
            .get();

        const batch = db.batch();
        let updateCount = 0;

        for (const doc of lookupSnapshot.docs) {
          const data = doc.data();
          const sensorRef = db.doc(data.sensorDocPath);

          // Mark sensor as offline
          batch.update(sensorRef, {
            isOnline: false,
          });

          updateCount++;

          // Firestore batch limit is 500 operations
          if (updateCount >= 500) {
            await batch.commit();
            updateCount = 0;
          }
        }

        if (updateCount > 0) {
          await batch.commit();
        }

        console.log(`Marked ${lookupSnapshot.size} sensors as offline`);
      } catch (error) {
        console.error('Error checking sensor status:', error);
      }
    });
