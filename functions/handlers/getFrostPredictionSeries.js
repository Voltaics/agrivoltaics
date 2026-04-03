const functions = require('firebase-functions');
const {bigquery} = require('../lib/firebase');

const FROST_TABLE_DATASET_ID = 'sensor_data';
const FROST_TABLE_ID = 'frost_predictions';
const READINGS_TABLE_DATASET_ID = 'sensor_data';
const READINGS_TABLE_ID = 'readings';

/**
 * Determines the appropriate time bucketing configuration based on the
 * requested date range. This is used to dynamically adjust the resolution
 * of the time series to balance detail and performance.
 *
 * Bucketing strategy:
 * - <= 7 days   → 15-minute intervals
 * - <= 31 days  → 1-hour intervals
 * - > 31 days   → 1-day intervals
 *
 * @param {Date} startDate - Start of the requested time range.
 * @param {Date} endDate - End of the requested time range.
 * @return {{intervalLabel: string, bucketSeconds: number}} Object containing:
 *   - intervalLabel: A string identifier for the interval (e.g., 'MINUTE_15', 'HOUR_1', 'DAY_1')
 *   - bucketSeconds: The bucket size in seconds used for time aggregation in BigQuery
 */
function getBucketConfig(startDate, endDate) {
  const diffMs = endDate.getTime() - startDate.getTime();
  const diffDays = diffMs / (1000 * 60 * 60 * 24);

  if (diffDays <= 7) {
    return {
      intervalLabel: 'MINUTE_15',
      bucketSeconds: 900,
    };
  }

  if (diffDays <= 31) {
    return {
      intervalLabel: 'HOUR_1',
      bucketSeconds: 3600,
    };
  }

  return {
    intervalLabel: 'DAY_1',
    bucketSeconds: 86400,
  };
}

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

    if (endDate <= startDate) {
      return res.status(400).json({
        success: false,
        error: 'End time must be after start time.',
      });
    }

    const {intervalLabel, bucketSeconds} = getBucketConfig(startDate, endDate);

    const sql = `
      WITH
        params AS (
          SELECT
            TIMESTAMP(@start) AS start_ts,
            TIMESTAMP(@end) AS end_ts,
            @zoneId AS zone_id,
            @bucketSeconds AS bucket_seconds
        ),

        reads AS (
          SELECT
            TIMESTAMP_SECONDS(DIV(UNIX_SECONDS(r.timestamp), p.bucket_seconds) * p.bucket_seconds) AS bucket_ts,
            AVG(IF(r.field = 'temperature', r.value, NULL)) AS temperature,
            AVG(IF(r.field = 'humidity', r.value, NULL)) AS humidity,
            AVG(IF(r.field = 'soilTemperature', r.value, NULL)) AS soilTemperature
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
            TIMESTAMP_SECONDS(DIV(UNIX_SECONDS(fp.timestamp), p.bucket_seconds) * p.bucket_seconds) AS bucket_ts,
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
    `;

    const params = {
      organizationId,
      siteId,
      zoneId,
      start: startDate.toISOString(),
      end: endDate.toISOString(),
      timezone: resolvedTimezone,
      bucketSeconds,
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
      interval: intervalLabel,
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
