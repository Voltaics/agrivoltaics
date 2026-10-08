/**
 * BigQuery context fetch for the frost engine: latest per-field values plus
 * the temperature readings closest to 15/30/60/120 minutes ago, which
 * derivations.js's cooling-rate functions need. Modeled directly on
 * fetchRecentFrostContext in functions/lib/alertHelpers.js.
 */

const {bigquery} = require('../firebase');
const {toNumberOrNull} = require('./utils');

// Covers the 120-minute cooling-rate lookback plus a margin for irregular
// reporting; durations/accumulators live in frostEngineState (see
// stateStore.js/accumulators.js), not recomputed from long history each tick.
const CONTEXT_WINDOW_MINUTES = 150;

const LOOKBACK_WINDOWS_MINUTES = [15, 30, 60, 120];

const CONTEXT_FIELDS = [
  'temperature', 'humidity', 'windSpeed', 'windGust', 'leafMoisture',
  'soilTemperature', 'soilMoisture', 'light',
];

/**
 * @param {Array<Object>} series - Entries shaped {value, unit, sensorId, timestamp, primarySensor, timestampMs}.
 * @param {number} targetMs
 * @return {Object|null} The entry with timestamp closest to targetMs, or null if series is empty.
 */
function pickClosestToTargetTime(series, targetMs) {
  let best = null;
  let bestDistance = Number.POSITIVE_INFINITY;

  for (const entry of series) {
    const distance = Math.abs(entry.timestampMs - targetMs);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = entry;
    }
  }

  return best;
}

/**
 * @param {Object} args
 * @param {string} args.organizationId
 * @param {string} args.siteId
 * @param {string} args.zoneId
 * @param {Date} args.now
 * @return {Promise<{current: Object, temperatureAt: Object}>}
 *   `current` maps field -> {value, unit, sensorId, timestamp, primarySensor} for the latest reading.
 *   `temperatureAt` maps 15|30|60|120 -> the same shape, for the temperature reading closest to that many minutes ago.
 */
async function fetchRecentEngineContext({organizationId, siteId, zoneId, now}) {
  const endIso = now.toISOString();
  const startIso = new Date(now.getTime() - CONTEXT_WINDOW_MINUTES * 60 * 1000).toISOString();

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
      AND field IN UNNEST(@fields)
      AND timestamp BETWEEN TIMESTAMP(@startIso) AND TIMESTAMP(@endIso)
    ORDER BY timestamp DESC
  `;

  const [rows] = await bigquery.query({
    query,
    params: {
      organizationId,
      siteId,
      zoneId,
      fields: CONTEXT_FIELDS,
      startIso,
      endIso,
    },
  });

  const current = {};
  const temperatureSeries = [];

  for (const row of rows) {
    const value = toNumberOrNull(row.value);
    if (value === null) continue;

    const ts = new Date(row.timestamp.value || row.timestamp);
    const entry = {
      value,
      unit: row.unit || '',
      sensorId: row.sensorId || null,
      timestamp: ts.toISOString(),
      primarySensor: !!row.primarySensor,
    };

    // Rows are ordered DESC, so the first hit per field is the latest.
    if (!current[row.field]) current[row.field] = entry;

    if (row.field === 'temperature') {
      temperatureSeries.push(Object.assign({timestampMs: ts.getTime()}, entry));
    }
  }

  const temperatureAt = {};
  for (const minutesAgo of LOOKBACK_WINDOWS_MINUTES) {
    temperatureAt[minutesAgo] = pickClosestToTargetTime(
        temperatureSeries, now.getTime() - minutesAgo * 60 * 1000,
    );
  }

  return {current, temperatureAt};
}

module.exports = {
  fetchRecentEngineContext,
  CONTEXT_FIELDS,
  CONTEXT_WINDOW_MINUTES,
  LOOKBACK_WINDOWS_MINUTES,
};
