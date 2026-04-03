const functions = require('firebase-functions');
const {bigquery} = require('../lib/firebase');

const FROST_TABLE_DATASET_ID = 'sensor_data';
const FROST_TABLE_ID = 'frost_predictions';
const READINGS_TABLE_DATASET_ID = 'sensor_data';
const READINGS_TABLE_ID = 'readings';

/**
 * HTTPS Cloud Function: Get Frost Prediction Timeline (single-zone timeline)
 */
const getFrostPredictionSeries = functions.https.onRequest(async (req, res) => {
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
    // Keep this consistent with your existing getHistoricalSeries.js behavior.
    // If/when you re-enable auth there, do the same here.

    const {
      organizationId,
      siteId,
      zoneId,
      start,
      end,
      timezone,
    } = req.body || {};

    const resolvedTimezone = timezone || 'America/New_York';

    if (!organizationId || !siteId || !zoneId || !start || !end) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: organizationId, siteId, zoneId, start, end',
      });
    }

    const startDate = new Date(start);
    const endDate = new Date(end);

    if (Number.isNaN(startDate.getTime()) || Number.isNaN(endDate.getTime())) {
      return res.status(400).json({
        success: false,
        error: 'Invalid start or end timestamp.',
      });
    }

    const sql = `
      WITH
        params AS (
          SELECT
            TIMESTAMP(@start) AS start_ts,
            TIMESTAMP(@end) AS end_ts,
            @zoneId AS zone_id
        ),

        reads AS (
          SELECT
            TIMESTAMP_SECONDS(DIV(UNIX_SECONDS(r.timestamp), 900) * 900) AS bucket_ts,
            MAX(IF(r.field = 'temperature', r.value, NULL)) AS temperature,
            MAX(IF(r.field = 'humidity', r.value, NULL)) AS humidity,
            MAX(IF(r.field = 'soilTemperature', r.value, NULL)) AS soilTemperature
          FROM \`${bigquery.projectId}.${READINGS_TABLE_DATASET_ID}.${READINGS_TABLE_ID}\` r
          CROSS JOIN params p
          WHERE
            r.timestamp >= p.start_ts
            AND r.timestamp < p.end_ts
            AND r.organizationId = @organizationId
            AND r.siteId = @siteId
            AND r.zoneId = p.zone_id
            AND r.field IN ('temperature', 'humidity', 'soilTemperature')
            AND r.primarySensor = TRUE
          GROUP BY bucket_ts
        ),

        preds AS (
          SELECT
            TIMESTAMP_SECONDS(DIV(UNIX_SECONDS(fp.timestamp), 900) * 900) AS bucket_ts,
            ARRAY_AGG(fp.probability_percent ORDER BY fp.timestamp DESC LIMIT 1)[OFFSET(0)] AS probability_percent
          FROM \`${bigquery.projectId}.${FROST_TABLE_DATASET_ID}.${FROST_TABLE_ID}\` fp
          CROSS JOIN params p
          WHERE
            fp.timestamp >= p.start_ts
            AND fp.timestamp < p.end_ts
            AND fp.zoneId = p.zone_id
          GROUP BY bucket_ts
        ),

        joined AS (
          SELECT
            r.bucket_ts,
            r.temperature,
            r.humidity,
            r.soilTemperature,
            NULLIF(p.probability_percent, -1) AS pred_raw
          FROM reads r
          LEFT JOIN preds p
            ON p.bucket_ts = r.bucket_ts
        )

      SELECT
        bucket_ts AS timestamp,
        temperature,
        humidity,
        soilTemperature,
        COALESCE(
          LAST_VALUE(pred_raw IGNORE NULLS) OVER (
            ORDER BY bucket_ts
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
          ),
          0
        ) AS predictedChance
      FROM joined
      ORDER BY timestamp
      LIMIT 1000
    `;

    const params = {
      organizationId,
      siteId,
      zoneId,
      start: startDate.toISOString(),
      end: endDate.toISOString(),
      timezone: resolvedTimezone,
    };

    const [rows] = await bigquery.query({
      query: sql,
      params,
    });

    const points = rows.map((row) => ({
      timestamp: row.timestamp.value || row.timestamp,
      temperature: row.temperature == null ? null : Number(row.temperature),
      humidity: row.humidity == null ? null : Number(row.humidity),
      soilTemperature: row.soilTemperature == null ? null : Number(row.soilTemperature),
      predictedChance: row.predictedChance == null ? 0 : Number(row.predictedChance),
    }));

    return res.status(200).json({
      success: true,
      zoneId,
      siteId,
      organizationId,
      timezone: resolvedTimezone,
      interval: 'MINUTE_15',
      points,
    });
  } catch (error) {
    console.error('Frost prediction series error:', error);
    return res.status(500).json({
      success: false,
      error: error.message || 'Internal server error',
    });
  }
});

module.exports = {getFrostPredictionSeries};
