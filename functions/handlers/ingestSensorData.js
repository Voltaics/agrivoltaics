const functions = require('firebase-functions');
const {Timestamp} = require('firebase-admin/firestore');
const {db, bigquery, DATASET_ID, TABLE_ID} = require('../lib/firebase');

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

        const zoneDocPath = `organizations/${organizationId}/sites/${siteId}/zones/${zoneId}`;
        const zoneDoc = await db.doc(zoneDocPath).get();
        const zoneData = zoneDoc.exists ? zoneDoc.data() : {};

        if (sensorData.status !== 'active') {
          errors.push({
            index: i,
            sensorId,
            error: `Sensor is inactive. Status: ${sensorData.status || 'unknown'}`,
          });
          continue;
        }

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

        const date = new Date(timestamp * 1000);
        const isoTimestamp = date.toISOString();

        const sensorBqRows = Object.entries(readings).map(([field, reading]) => {
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
