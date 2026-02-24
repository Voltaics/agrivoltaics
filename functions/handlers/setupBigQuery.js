const functions = require('firebase-functions');
const {bigquery, DATASET_ID, TABLE_ID} = require('../lib/firebase');

/**
 * HTTPS Cloud Function: Setup BigQuery
 *
 * One-time setup function to create BigQuery dataset and table with optimized
 * configuration for time-series sensor data.
 *
 * @param {Object} req - Express request object
 * @param {Object} res - Express response object
 * @returns {Promise<void>} JSON response with setup status
 */
const setupBigQuery = functions.https.onRequest(async (req, res) => {
  try {
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

    const table = dataset.table(TABLE_ID);
    const [tableExists] = await table.exists();

    if (!tableExists) {
      const options = {
        schema: expectedSchema,
        timePartitioning: {
          type: 'DAY',
          field: 'timestamp',
          expirationMs: null,
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
    }

    const [metadata] = await table.getMetadata();
    const currentSchema = metadata.schema.fields;

    const schemaMatches = expectedSchema.every((expectedField) => {
      const currentField = currentSchema.find((f) => f.name === expectedField.name);
      if (!currentField) {
        console.log(`Missing field: ${expectedField.name}`);
        return false;
      }
      if (currentField.type !== expectedField.type) {
        console.log(
            `Type mismatch for ${expectedField.name}: expected ${expectedField.type}, got ${currentField.type}`,
        );
        return false;
      }
      const currentMode = currentField.mode || 'NULLABLE';
      if (currentMode !== expectedField.mode) {
        console.log(
            `Mode mismatch for ${expectedField.name}: expected ${expectedField.mode}, got ${currentMode}`,
        );
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
    }

    return res.status(400).json({
      success: false,
      message: 'BigQuery table exists but schema does not match',
      dataset: DATASET_ID,
      table: TABLE_ID,
      schemaValid: false,
      expectedSchema: expectedSchema,
      currentSchema: currentSchema,
    });
  } catch (error) {
    console.error('BigQuery setup error:', error);
    return res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

module.exports = {setupBigQuery};
