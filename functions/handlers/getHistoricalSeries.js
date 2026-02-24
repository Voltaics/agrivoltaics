const functions = require('firebase-functions');
const {bigquery, DATASET_ID, TABLE_ID} = require('../lib/firebase');

const MS_PER_DAY = 24 * 60 * 60 * 1000;

const pickInterval = (startMillis, endMillis) => {
  const range = Math.max(0, endMillis - startMillis);

  if (range <= MS_PER_DAY) return 'MINUTE_15';
  if (range <= 7 * MS_PER_DAY) return 'HOUR';
  if (range <= 14 * MS_PER_DAY) return 'DAY';
  if (range <= 90 * MS_PER_DAY) return 'WEEK';
  return 'MONTH';
};

/**
 * HTTPS Cloud Function: Get Historical Series (multi-graph)
 */
const getHistoricalSeries = functions.https.onRequest(async (req, res) => {
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
    // TODO: Re-enable authentication before production
    // const authHeader = req.headers.authorization || '';
    // const match = authHeader.match(/^Bearer (.+)$/);
    // if (!match) {
    //   return res.status(401).json({
    //     success: false,
    //     error: 'Missing or invalid auth token.',
    //   });
    // }
    //
    // await admin.auth().verifyIdToken(match[1]);

    const {
      organizationId,
      siteId,
      zoneIds,
      readings,
      start,
      end,
      interval,
      sensorId,
      timezone,
      aggregation,
    } = req.body || {};

    // Resolve aggregation function (avg/min/max), default avg
    const allowedAggregations = new Set(['AVG', 'MIN', 'MAX']);
    const resolvedAggregation = allowedAggregations.has((aggregation || '').toUpperCase()) ?
      aggregation.toUpperCase() :
      'AVG';

    // Default to America/New_York if timezone not provided
    const resolvedTimezone = timezone || 'America/New_York';

    if (!organizationId || !siteId) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: organizationId, siteId',
      });
    }

    if (!Array.isArray(zoneIds) || zoneIds.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'Missing or invalid zoneIds (non-empty array required)',
      });
    }

    if (!Array.isArray(readings) || readings.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'Missing or invalid readings (non-empty array required)',
      });
    }

    if (!start || !end) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: start, end',
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

    const requestedInterval = typeof interval === 'string' ? interval.toUpperCase() : null;
    const allowedIntervals = new Set(['MINUTE_15', 'HOUR', 'DAY', 'WEEK', 'MONTH']);
    const resolvedInterval = allowedIntervals.has(requestedInterval) ?
      requestedInterval :
      pickInterval(startDate.getTime(), endDate.getTime());

    // Build the bucket expression — MINUTE_15 requires manual 15-min floor since
    // TIMESTAMP_TRUNC does not support sub-hour intervals.
    const bucketExpr = resolvedInterval === 'MINUTE_15' ?
      'TIMESTAMP_SECONDS(DIV(UNIX_SECONDS(timestamp), 900) * 900)' :
      `TIMESTAMP_TRUNC(timestamp, ${resolvedInterval}, @timezone)`;

    const sql = `
      SELECT
        field,
        zoneId,
        ${bucketExpr} AS bucket,
        ${resolvedAggregation}(value) AS agg_value,
        ANY_VALUE(unit) AS unit
      FROM \`${bigquery.projectId}.${DATASET_ID}.${TABLE_ID}\`
      WHERE organizationId = @organizationId
        AND siteId = @siteId
        AND zoneId IN UNNEST(@zoneIds)
        AND field IN UNNEST(@fields)
        AND timestamp BETWEEN TIMESTAMP(@start) AND TIMESTAMP(@end)
        ${sensorId ? 'AND sensorId = @sensorId' : 'AND primarySensor = TRUE'}
      GROUP BY field, zoneId, bucket
      ORDER BY field, zoneId, bucket ASC
    `;

    const params = {
      organizationId,
      siteId,
      zoneIds,
      fields: readings,
      start: startDate.toISOString(),
      end: endDate.toISOString(),
      timezone: resolvedTimezone,
    };

    if (sensorId) {
      params.sensorId = sensorId;
    }

    const [rows] = await bigquery.query({query: sql, params});

    const graphsMap = new Map();

    rows.forEach((row) => {
      const field = row.field;
      const zoneId = row.zoneId;
      const bucket = row.bucket.value || row.bucket;
      const value = Number(row.agg_value);
      const unit = row.unit || null;

      if (!graphsMap.has(field)) {
        graphsMap.set(field, {field, unit, series: new Map()});
      }

      const graph = graphsMap.get(field);
      if (!graph.series.has(zoneId)) {
        graph.series.set(zoneId, {zoneId, points: []});
      }

      graph.series.get(zoneId).points.push({t: bucket, v: value});
    });

    const graphs = Array.from(graphsMap.values()).map((graph) => ({
      field: graph.field,
      unit: graph.unit,
      series: Array.from(graph.series.values()),
    }));

    return res.status(200).json({
      success: true,
      interval: resolvedInterval,
      aggregation: resolvedAggregation,
      graphs,
    });
  } catch (error) {
    console.error('Historical series error:', error);
    return res.status(500).json({
      success: false,
      error: error.message || 'Internal server error',
    });
  }
});

module.exports = {getHistoricalSeries};
