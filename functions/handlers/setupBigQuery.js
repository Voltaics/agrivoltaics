const functions = require('firebase-functions');
const {bigquery, DATASET_ID, TABLE_ID, ALERTS_TABLE_ID} = require('../lib/firebase');

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

    const results = {};

    // ── Readings table ────────────────────────────────────────────────────
    const readingsSchema = [
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

    const readingsTable = dataset.table(TABLE_ID);
    const [readingsTableExists] = await readingsTable.exists();

    if (!readingsTableExists) {
      await dataset.createTable(TABLE_ID, {
        schema: readingsSchema,
        timePartitioning: {type: 'DAY', field: 'timestamp', expirationMs: null},
        clustering: {fields: ['sensorId', 'field']},
        description: 'Sensor readings with daily partitioning and clustering by sensor/field',
      });
      console.log(`Created table: ${TABLE_ID}`);
      results[TABLE_ID] = 'created';
    } else {
      const [metadata] = await readingsTable.getMetadata();
      const currentSchema = metadata.schema.fields;
      const schemaMatches = readingsSchema.every((expected) => {
        const current = currentSchema.find((f) => f.name === expected.name);
        return current &&
          current.type === expected.type &&
          (current.mode || 'NULLABLE') === expected.mode;
      }) && currentSchema.length === readingsSchema.length;

      if (!schemaMatches) {
        return res.status(400).json({
          success: false,
          message: `${TABLE_ID} exists but schema does not match`,
          expected: readingsSchema,
          current: currentSchema,
        });
      }
      results[TABLE_ID] = 'exists';
    }

    // ── Alerts table ──────────────────────────────────────────────────────
    const alertsSchema = [
      {name: 'triggeredAt', type: 'TIMESTAMP', mode: 'REQUIRED'},
      {name: 'organizationId', type: 'STRING', mode: 'REQUIRED'},
      {name: 'siteId', type: 'STRING', mode: 'NULLABLE'},
      {name: 'zoneId', type: 'STRING', mode: 'NULLABLE'},
      {name: 'sensorId', type: 'STRING', mode: 'NULLABLE'},
      {name: 'ruleId', type: 'STRING', mode: 'REQUIRED'},
      {name: 'ruleName', type: 'STRING', mode: 'REQUIRED'},
      {name: 'fieldAlias', type: 'STRING', mode: 'REQUIRED'},
      {name: 'value', type: 'FLOAT', mode: 'REQUIRED'},
      {name: 'threshold', type: 'FLOAT', mode: 'REQUIRED'},
      {name: 'operator', type: 'STRING', mode: 'REQUIRED'},
      {name: 'severity', type: 'STRING', mode: 'NULLABLE'},
      {name: 'unit', type: 'STRING', mode: 'NULLABLE'},
    ];

    const alertsTable = dataset.table(ALERTS_TABLE_ID);
    const [alertsTableExists] = await alertsTable.exists();

    if (!alertsTableExists) {
      await dataset.createTable(ALERTS_TABLE_ID, {
        schema: alertsSchema,
        timePartitioning: {type: 'DAY', field: 'triggeredAt'},
        clustering: {fields: ['organizationId', 'ruleId']},
        description: 'Alert rule trigger events with daily partitioning',
      });
      console.log(`Created table: ${ALERTS_TABLE_ID}`);
      results[ALERTS_TABLE_ID] = 'created';
    } else {
      console.log(`Table ${ALERTS_TABLE_ID} already exists`);
      results[ALERTS_TABLE_ID] = 'exists';
    }

    return res.status(200).json({success: true, dataset: DATASET_ID, tables: results});
  } catch (error) {
    console.error('BigQuery setup error:', error);
    return res.status(500).json({success: false, error: error.message});
  }
});

module.exports = {setupBigQuery};
