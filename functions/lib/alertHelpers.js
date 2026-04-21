/**
 * Alert helper utilities for FCM push-notification alert evaluation.
 *
 * These functions are called from ingestSensorData after a successful
 * BigQuery insert to check alert rules and dispatch FCM notifications.
 */

const {db, messaging, bigquery, DATASET_ID, ALERTS_TABLE_ID} = require('./firebase');
const {FieldValue} = require('firebase-admin/firestore');

/**
 * Parse a 'MM/dd' date string into {month, day}.
 * @param {string} str
 * @return {{month: number, day: number}}
 */
function parseMmDd(str) {
  const parts = str.split('/');
  return {month: parseInt(parts[0], 10), day: parseInt(parts[1], 10)};
}

/**
 * Returns true when today (UTC) falls within the [start, end] MM/dd window.
 * Handles year wrap-around.
 * @param {Date} now
 * @param {string|null} start
 * @param {string|null} end
 * @return {boolean}
 */
function isWithinActiveDateRange(now, start, end) {
  if (!start || !end) return true;

  const s = parseMmDd(start);
  const e = parseMmDd(end);

  const nowVal = (now.getUTCMonth() + 1) * 100 + now.getUTCDate();
  const startVal = s.month * 100 + s.day;
  const endVal = e.month * 100 + e.day;

  if (startVal <= endVal) {
    return nowVal >= startVal && nowVal <= endVal;
  }
  return nowVal >= startVal || nowVal <= endVal;
}

/**
 * Evaluate a comparison condition.
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
 * Convert to finite number or null.
 * @param {*} value
 * @return {number|null}
 */
function toNumberOrNull(value) {
  if (value === null || value === undefined) return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

/**
 * Return value unless it is null/undefined, else fallback.
 * Compatible with older ESLint/parser configs that reject ??.
 * @param {*} value
 * @param {*} fallback
 * @return {*}
 */
function defaultIfNull(value, fallback) {
  return value != null ? value : fallback;
}

const FROST_TIMEZONE = 'America/New_York';
const FROST_CLEAR_SKY_DROP_RATE_DEFAULT = 1000.0; // lux/hour, tune from field data

/**
 * Get local date parts in a specific timezone.
 * @param {Date} date
 * @param {string} timeZone
 * @return {{year:number, month:number, day:number, hour:number, minute:number}}
 */
function getZonedParts(date, timeZone) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(date);

  const map = {};
  for (const part of parts) {
    if (part.type !== 'literal') {
      map[part.type] = parseInt(part.value, 10);
    }
  }

  return {
    year: map.year,
    month: map.month,
    day: map.day,
    hour: map.hour,
    minute: map.minute,
  };
}

/**
 * Get YYYY-MM-DD key in a specific timezone.
 * @param {Date} date
 * @param {string} timeZone
 * @return {string}
 */
function getZonedDateKey(date, timeZone) {
  const p = getZonedParts(date, timeZone);
  const mm = String(p.month).padStart(2, '0');
  const dd = String(p.day).padStart(2, '0');
  return `${p.year}-${mm}-${dd}`;
}

/**
 * Estimate the rate of lux drop from 4 PM local time until sunset proxy.
 * Sunset proxy = first light reading at or below lightMax after 4 PM.
 *
 * @param {Array<Object>} lightSeries
 * @param {Date} now
 * @param {number} lightMax
 * @return {number|null}
 */
function computePreSunsetLuxDropRate(lightSeries, now, lightMax) {
  if (!Array.isArray(lightSeries) || lightSeries.length === 0) return null;

  const todayKey = getZonedDateKey(now, FROST_TIMEZONE);

  const sameDaySeries = lightSeries
      .map((entry) => {
        const ts = new Date(entry.timestamp);
        const zoned = getZonedParts(ts, FROST_TIMEZONE);
        return {
          ...entry,
          _zoned: zoned,
          _dateKey: `${zoned.year}-${String(zoned.month).padStart(2, '0')}-${String(zoned.day).padStart(2, '0')}`,
        };
      })
      .filter((entry) => entry._dateKey === todayKey)
      .sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));

  if (sameDaySeries.length === 0) return null;

  const startEntry = sameDaySeries.find((entry) => {
    return entry._zoned.hour > 16 || (entry._zoned.hour === 16 && entry._zoned.minute >= 0);
  });

  if (!startEntry || startEntry.value == null) return null;

  const sunsetEntry = sameDaySeries.find((entry) => {
    const after4pm =
      entry._zoned.hour > 16 || (entry._zoned.hour === 16 && entry._zoned.minute >= 0);
    return after4pm && entry.value != null && entry.value <= lightMax;
  });

  if (!sunsetEntry || sunsetEntry.value == null) return null;

  const startTs = new Date(startEntry.timestamp).getTime();
  const sunsetTs = new Date(sunsetEntry.timestamp).getTime();
  const elapsedHours = (sunsetTs - startTs) / (1000 * 60 * 60);

  if (elapsedHours <= 0) return null;

  return (startEntry.value - sunsetEntry.value) / elapsedHours;
}

/**
 * Group BigQuery reading rows by exact timestamp and field.
 * Returns timestamps sorted ascending plus a row map.
 *
 * @param {Array<Object>} rows
 * @return {{timestamps: string[], byTimestamp: Object}}
 */
function groupRowsByTimestamp(rows) {
  const byTimestamp = {};

  for (const row of rows) {
    const ts = new Date(row.timestamp.value || row.timestamp).toISOString();
    if (!byTimestamp[ts]) byTimestamp[ts] = {};

    byTimestamp[ts][row.field] = {
      value: toNumberOrNull(row.value),
      unit: row.unit || '',
      sensorId: row.sensorId || null,
      timestamp: ts,
      primarySensor: !!row.primarySensor,
    };
  }

  const timestamps = Object.keys(byTimestamp).sort();
  return {timestamps, byTimestamp};
}

/**
 * Pick latest entry for a field from grouped context.
 * @param {{timestamps: string[], byTimestamp: Object}} grouped
 * @param {string} field
 * @return {Object|null}
 */
function getLatestFieldEntry(grouped, field) {
  for (let i = grouped.timestamps.length - 1; i >= 0; i--) {
    const ts = grouped.timestamps[i];
    const entry = grouped.byTimestamp[ts][field];
    if (entry && entry.value != null) return entry;
  }
  return null;
}

/**
 * Compute average numeric value for field across grouped rows.
 * @param {{timestamps: string[], byTimestamp: Object}} grouped
 * @param {string} field
 * @return {number|null}
 */
function getAverageFieldValue(grouped, field) {
  let sum = 0;
  let count = 0;

  for (const ts of grouped.timestamps) {
    const entry = grouped.byTimestamp[ts][field];
    if (entry && entry.value != null) {
      sum += entry.value;
      count++;
    }
  }

  return count > 0 ? sum / count : null;
}

/**
 * Build an alert summary string for a threshold rule.
 * @param {Object} rule
 * @param {Object} fieldEntry
 * @return {{title: string, body: string}}
 */
function buildThresholdAlertMessage(rule, fieldEntry) {
  const operatorLabel =
    {gt: '>', lt: '<', gte: '≥', lte: '≤', eq: '='}[rule.operator] || rule.operator;

  const title = `Alert: ${rule.name}`;
  const body =
    `${rule.fieldAlias} is ${fieldEntry.value}${fieldEntry.unit || ''} ` +
    `(threshold: ${operatorLabel} ${rule.threshold}${fieldEntry.unit || ''})`;

  return {title, body};
}

/**
 * Build an alert summary string for a frost warning rule.
 * @param {Object} rule
 * @param {Object} details
 * @return {{title: string, body: string}}
 */
function buildFrostAlertMessage(rule, details) {
  const title = `Alert: ${rule.name}`;
  const body =
    `Frost warning conditions detected: ` +
    `temp ${details.airTempF}°F, humidity ${details.humidity}%, ` +
    `soil temp ${details.soilTempF}°F, ` +
    `temp drop ${details.tempDropRateFPerHour.toFixed(1)}°F/hr` +
    (details.light != null ? `, light ${details.light}` : '') +
    (details.preSunsetLuxDropRate != null ?
      `, pre-sunset lux drop ${details.preSunsetLuxDropRate.toFixed(0)} lux/hr` :
      '') +
    (details.anticipateSkyClearingDuringNight ?
      `, anticipating overnight clearing` :
      '');

  return {title, body};
}

/**
 * Build an alert summary string for a mold risk rule.
 * @param {Object} rule
 * @param {Object} details
 * @return {{title: string, body: string}}
 */
function buildMoldAlertMessage(rule, details) {
  const title = `Alert: ${rule.name}`;
  const body =
    `Mold risk conditions detected: ` +
    `qualifying duration ${details.qualifyingHours.toFixed(1)} hr, ` +
    `avg humidity ${details.avgHumidity.toFixed(1)}%, ` +
    `avg temp ${details.avgTempF.toFixed(1)}°F` +
    (details.avgLight != null ? `, avg light ${details.avgLight.toFixed(1)}` : '') +
    (details.avgSoilMoisture != null ?
      `, avg soil moisture ${details.avgSoilMoisture.toFixed(1)}` :
      '');

  return {title, body};
}

/**
 * Build an alert summary string for a black rot risk rule.
 * @param {Object} rule
 * @param {Object} details
 * @return {{title: string, body: string}}
 */
function buildBlackRotAlertMessage(rule, details) {
  const title = `Alert: ${rule.name}`;
  const body =
    `Black rot risk conditions detected: ` +
    `soil moisture jump ${details.soilMoistureJump.toFixed(1)}, ` +
    `event humidity ${details.eventHumidity.toFixed(1)}%, ` +
    `event temp ${details.eventTempF.toFixed(1)}°F, ` +
    `follow-up warm/humid coverage ${(details.followupCoverage * 100).toFixed(0)}%`;

  return {title, body};
}

/**
 * Fetch FCM {uid, token} pairs for a list of user IDs.
 * @param {string[]} userIds
 * @return {Promise<Array<{uid: string, token: string}>>}
 */
async function getFcmTokenPairs(userIds) {
  if (!userIds || userIds.length === 0) return [];

  const userDocs = await Promise.all(
      userIds.map((uid) => db.doc(`users/${uid}`).get()),
  );

  const pairs = [];
  for (const doc of userDocs) {
    if (!doc.exists) continue;
    const tokens = doc.data().fcmTokens;
    if (!Array.isArray(tokens)) continue;
    for (const token of tokens) {
      if (token) pairs.push({uid: doc.id, token});
    }
  }
  return pairs;
}

/**
 * Write a single in-app notification document.
 * @param {Object} args
 * @return {Promise<void>}
 */
async function writeInAppNotification({
  userId, organizationId, title, body, type, referenceId, expiresAt,
}) {
  const ref = db.collection('notifications').doc();
  await ref.set({
    userId,
    organizationId,
    title,
    body,
    type: type || 'alert',
    referenceType: 'alert',
    referenceId: referenceId || null,
    isRead: false,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt: expiresAt || null,
  });
}

/**
 * Query recent BigQuery readings for fields needed by frost warning.
 *
 * Expects the sensor readings table to be in dataset sensor_data and table readings.
 * If your table name differs, change `readings` below.
 *
 * @param {Object} args
 * @param {string} args.organizationId
 * @param {string} args.siteId
 * @param {string} args.zoneId
 * @param {Date} args.now
 * @return {Promise<Object>}
 */
async function fetchRecentFrostContext({organizationId, siteId, zoneId, now}) {
  const endIso = now.toISOString();
  const startIso = new Date(now.getTime() - 12 * 60 * 60 * 1000).toISOString();

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
      AND field IN ('temperature', 'humidity', 'soilTemperature', 'light')
      AND timestamp BETWEEN TIMESTAMP(@startIso) AND TIMESTAMP(@endIso)
    ORDER BY timestamp DESC
  `;

  const [rows] = await bigquery.query({
    query,
    params: {
      organizationId,
      siteId,
      zoneId,
      startIso,
      endIso,
    },
  });

  const latest = {};
  const oneHourAgoTargetMs = now.getTime() - 60 * 60 * 1000;
  let bestTempOneHourAgo = null;
  let bestTempDistanceMs = Number.POSITIVE_INFINITY;

  const lightSeries = [];

  for (const row of rows) {
    const field = row.field;
    const value = toNumberOrNull(row.value);
    if (value == null) continue;

    const ts = new Date(row.timestamp.value || row.timestamp);
    const entry = {
      value,
      unit: row.unit || '',
      sensorId: row.sensorId || null,
      timestamp: ts.toISOString(),
      primarySensor: !!row.primarySensor,
    };

    if (!latest[field]) {
      latest[field] = entry;
    }

    if (field === 'light') {
      lightSeries.push(entry);
    }

    if (field === 'temperature') {
      const distanceMs = Math.abs(ts.getTime() - oneHourAgoTargetMs);
      if (distanceMs < bestTempDistanceMs) {
        bestTempDistanceMs = distanceMs;
        bestTempOneHourAgo = entry;
      }
    }
  }

  return {
    current: {
      temperature: latest.temperature || null,
      humidity: latest.humidity || null,
      soilTemperature: latest.soilTemperature || null,
      light: latest.light || null,
    },
    oneHourAgoTemperature: bestTempOneHourAgo,
    lightSeries,
  };
}

/**
 * Query recent BigQuery readings for fields needed by mold risk.
 *
 * @param {Object} args
 * @param {string} args.organizationId
 * @param {string} args.siteId
 * @param {string} args.zoneId
 * @param {Date} args.now
 * @param {number} args.durationHours
 * @return {Promise<Object>}
 */
async function fetchRecentMoldContext({
  organizationId,
  siteId,
  zoneId,
  now,
  durationHours,
}) {
  const windowHours = durationHours + 2;
  const endIso = now.toISOString();
  const startIso = new Date(now.getTime() - windowHours * 60 * 60 * 1000)
      .toISOString();

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
      AND field IN ('temperature', 'humidity', 'light', 'soilMoisture')
      AND timestamp BETWEEN TIMESTAMP(@startIso) AND TIMESTAMP(@endIso)
    ORDER BY timestamp ASC
  `;

  const [rows] = await bigquery.query({
    query,
    params: {
      organizationId,
      siteId,
      zoneId,
      startIso,
      endIso,
    },
  });

  return groupRowsByTimestamp(rows);
}

/**
 * Query recent BigQuery readings for fields needed by black rot risk.
 *
 * @param {Object} args
 * @param {string} args.organizationId
 * @param {string} args.siteId
 * @param {string} args.zoneId
 * @param {Date} args.now
 * @return {Promise<Object>}
 */
async function fetchRecentBlackRotContext({
  organizationId,
  siteId,
  zoneId,
  now,
}) {
  const endIso = now.toISOString();
  const startIso = new Date(now.getTime() - 72 * 60 * 60 * 1000).toISOString();

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
      AND field IN ('temperature', 'humidity', 'soilMoisture')
      AND timestamp BETWEEN TIMESTAMP(@startIso) AND TIMESTAMP(@endIso)
    ORDER BY timestamp ASC
  `;

  const [rows] = await bigquery.query({
    query,
    params: {
      organizationId,
      siteId,
      zoneId,
      startIso,
      endIso,
    },
  });

  return groupRowsByTimestamp(rows);
}

/**
 * Evaluate a frost warning rule.
 *
 * Default thresholds come from your PDF guidance:
 * - temp drop > 2 deg_F/hour
 * - humidity >= 90%
 * - air temp in the 30s
 * - soil temp <= 45 deg_F
 * - low light as nighttime/clear-sky proxy
 *
 * @param {Object} rule
 * @param {Object} frostContext
 * @return {{matched: boolean, details: (Object|null|undefined), fieldEntry: (Object|null|undefined)}}
 */
function evaluateFrostWarning(rule, frostContext) {
  const config = rule.ruleConfig || {};

  const tempDropRateThresholdRaw = toNumberOrNull(config.tempDropRateFPerHour);
  const humidityMinRaw = toNumberOrNull(config.humidityMin);
  const airTempMaxFRaw = toNumberOrNull(config.airTempMaxF);
  const soilTempMaxFRaw = toNumberOrNull(config.soilTempMaxF);
  const lightMaxRaw = toNumberOrNull(config.lightMax);
  const clearingLuxDropRatePerHourMinRaw =
    toNumberOrNull(config.clearingLuxDropRatePerHourMin);

  const tempDropRateThreshold =
    tempDropRateThresholdRaw != null ? tempDropRateThresholdRaw : 2.0;
  const humidityMin =
    humidityMinRaw != null ? humidityMinRaw : 90.0;
  const airTempMaxF =
    airTempMaxFRaw != null ? airTempMaxFRaw : 39.0;
  const soilTempMaxF =
    soilTempMaxFRaw != null ? soilTempMaxFRaw : 45.0;
  const lightMax =
    lightMaxRaw != null ? lightMaxRaw : 5000.0;
  const requireLowLight = config.requireLowLight !== false;
  const anticipateSkyClearingDuringNight =
    config.anticipateSkyClearingDuringNight === true;
  const clearingLuxDropRatePerHourMin =
    clearingLuxDropRatePerHourMinRaw != null ?
    clearingLuxDropRatePerHourMinRaw :
    FROST_CLEAR_SKY_DROP_RATE_DEFAULT;

  const air = frostContext.current.temperature;
  const humidity = frostContext.current.humidity;
  const soil = frostContext.current.soilTemperature;
  const light = frostContext.current.light;
  const oneHourAgoAir = frostContext.oneHourAgoTemperature;

  if (!air || !humidity || !soil || !oneHourAgoAir) {
    return {
      matched: false,
      reason: 'missing_required_context',
      missing: {
        air: !air,
        humidity: !humidity,
        soil: !soil,
        oneHourAgoAir: !oneHourAgoAir,
      },
    };
  }

  const airTempF = toNumberOrNull(air.value);
  const humidityPct = toNumberOrNull(humidity.value);
  const soilTempF = toNumberOrNull(soil.value);
  const lightValue = light ? toNumberOrNull(light.value) : null;
  const oneHourAgoTempF = toNumberOrNull(oneHourAgoAir.value);

  if (
    airTempF == null ||
    humidityPct == null ||
    soilTempF == null ||
    oneHourAgoTempF == null
  ) {
    return {
      matched: false,
      reason: 'invalid_numeric_context',
    };
  }

  const tempDropRateFPerHour = oneHourAgoTempF - airTempF;

  if (tempDropRateFPerHour <= tempDropRateThreshold) return {matched: false};
  if (humidityPct < humidityMin) return {matched: false};
  if (airTempF > airTempMaxF) return {matched: false};
  if (soilTempF > soilTempMaxF) return {matched: false};
  if (requireLowLight && (lightValue == null || lightValue > lightMax)) return {matched: false};
  const preSunsetLuxDropRate = computePreSunsetLuxDropRate(
      frostContext.lightSeries,
      new Date(air.timestamp),
      lightMax,
  );

  const clearEnoughBeforeSunset =
    preSunsetLuxDropRate != null &&
    preSunsetLuxDropRate >= clearingLuxDropRatePerHourMin;

  if (!anticipateSkyClearingDuringNight && !clearEnoughBeforeSunset) {
    return {
      matched: false,
      reason: 'cloud_cover_gate_failed',
      details: {
        anticipateSkyClearingDuringNight,
        preSunsetLuxDropRate,
        clearingLuxDropRatePerHourMin,
      },
    };
  }

  const details = {
    airTempF,
    humidity: humidityPct,
    soilTempF,
    light: lightValue,
    tempDropRateFPerHour,
    anticipateSkyClearingDuringNight,
    preSunsetLuxDropRate,
    clearingLuxDropRatePerHourMin,
  };

  // Reuse a fieldEntry-shaped object so dispatch can still attach a sensor/timestamp.
  const fieldEntry = {
    value: airTempF,
    unit: air.unit || '°F',
    sensorId: air.sensorId || '',
    timestamp: air.timestamp,
    primarySensor: air.primarySensor || false,
  };

  return {matched: true, details, fieldEntry};
}

/**
 * Evaluate a mold risk rule.
 *
 * Practical first pass:
 * - recent warm/humid readings over a configured duration
 * - low light (average or current)
 * - elevated average soil moisture
 *
 * @param {Object} rule
 * @param {Object} moldContext
 * @return {Object}
 */
function evaluateMoldRisk(rule, moldContext) {
  const config = rule.ruleConfig || {};
  const humidityMin = defaultIfNull(toNumberOrNull(config.humidityMin), 85.0);
  const tempMinF = defaultIfNull(toNumberOrNull(config.tempMinF), 68.0);
  const tempMaxF = defaultIfNull(toNumberOrNull(config.tempMaxF), 86.0);
  const lightMax = defaultIfNull(toNumberOrNull(config.lightMax), 5.0);
  const soilMoistureMin = defaultIfNull(
      toNumberOrNull(config.soilMoistureMin),
      40.0,
  );
  const durationHours = defaultIfNull(
      toNumberOrNull(config.durationHours),
      6.0,
  );

  let qualifyingCount = 0;
  let humiditySum = 0;
  let humidityCount = 0;
  let tempSum = 0;
  let tempCount = 0;

  for (const ts of moldContext.timestamps) {
    const bucket = moldContext.byTimestamp[ts];
    const tempEntry = bucket.temperature;
    const humidityEntry = bucket.humidity;

    if (humidityEntry && humidityEntry.value != null) {
      humiditySum += humidityEntry.value;
      humidityCount++;
    }

    if (tempEntry && tempEntry.value != null) {
      tempSum += tempEntry.value;
      tempCount++;
    }

    if (!tempEntry || !humidityEntry) continue;
    if (tempEntry.value == null || humidityEntry.value == null) continue;

    const tempOk = tempEntry.value >= tempMinF && tempEntry.value <= tempMaxF;
    const humidityOk = humidityEntry.value >= humidityMin;

    if (tempOk && humidityOk) {
      qualifyingCount++;
    }
  }

  const qualifyingHours = qualifyingCount * 0.25;
  if (qualifyingHours < durationHours) {
    return {matched: false};
  }

  const avgLight = getAverageFieldValue(moldContext, 'light');
  const currentLight = getLatestFieldEntry(moldContext, 'light');
  const lowLightOk =
    (avgLight != null && avgLight <= lightMax) ||
    (currentLight && currentLight.value != null && currentLight.value <= lightMax);

  if (!lowLightOk) {
    return {matched: false};
  }

  const avgSoilMoisture = getAverageFieldValue(moldContext, 'soilMoisture');
  if (avgSoilMoisture == null || avgSoilMoisture < soilMoistureMin) {
    return {matched: false};
  }

  const avgHumidity = humidityCount > 0 ? humiditySum / humidityCount : humidityMin;
  const avgTempF = tempCount > 0 ? tempSum / tempCount : tempMinF;

  const latestTemp = getLatestFieldEntry(moldContext, 'temperature');
  const fieldEntry = latestTemp || {
    value: avgTempF,
    unit: '°F',
    sensorId: '',
    timestamp: moldContext.timestamps.length > 0 ?
      moldContext.timestamps[moldContext.timestamps.length - 1] :
      new Date().toISOString(),
    primarySensor: false,
  };

  const details = {
    qualifyingHours,
    avgHumidity,
    avgTempF,
    avgLight,
    avgSoilMoisture,
  };

  return {matched: true, details, fieldEntry};
}

/**
 * Evaluate a black rot risk rule.
 *
 * Practical first pass:
 * - detect a soil moisture jump event
 * - confirm event humidity and temperature conditions
 * - confirm continued warm/humid follow-up coverage
 *
 * @param {Object} rule
 * @param {Object} blackRotContext
 * @return {Object}
 */
function evaluateBlackRotRisk(rule, blackRotContext) {
  const config = rule.ruleConfig || {};
  const humidityMin = defaultIfNull(toNumberOrNull(config.humidityMin), 90.0);
  const tempMinF = defaultIfNull(toNumberOrNull(config.tempMinF), 70.0);
  const tempMaxF = defaultIfNull(toNumberOrNull(config.tempMaxF), 85.0);
  const soilMoistureJumpMin = defaultIfNull(
      toNumberOrNull(config.soilMoistureJump),
      8.0,
  );
  const followupHours = defaultIfNull(
      toNumberOrNull(config.followupHours),
      48.0,
  );

  const timestamps = blackRotContext.timestamps;
  const byTimestamp = blackRotContext.byTimestamp;

  for (let i = 1; i < timestamps.length; i++) {
    const prevBucket = byTimestamp[timestamps[i - 1]];
    const currBucket = byTimestamp[timestamps[i]];

    const prevSoil = prevBucket.soilMoisture;
    const currSoil = currBucket.soilMoisture;
    const currHumidity = currBucket.humidity;
    const currTemp = currBucket.temperature;

    if (!prevSoil || !currSoil || !currHumidity || !currTemp) continue;
    if (
      prevSoil.value == null ||
      currSoil.value == null ||
      currHumidity.value == null ||
      currTemp.value == null
    ) {
      continue;
    }

    const soilJump = currSoil.value - prevSoil.value;
    const eventHumidityOk = currHumidity.value >= humidityMin;
    const eventTempOk = currTemp.value >= tempMinF && currTemp.value <= tempMaxF;

    if (soilJump < soilMoistureJumpMin || !eventHumidityOk || !eventTempOk) {
      continue;
    }

    const maxFollowupBuckets = Math.floor(followupHours * 4);
    let followupTotal = 0;
    let followupWarmHumid = 0;

    for (let j = i; j < timestamps.length && followupTotal < maxFollowupBuckets; j++) {
      const bucket = byTimestamp[timestamps[j]];
      const humidityEntry = bucket.humidity;
      const tempEntry = bucket.temperature;

      if (!humidityEntry || !tempEntry) continue;
      if (humidityEntry.value == null || tempEntry.value == null) continue;

      followupTotal++;
      if (
        humidityEntry.value >= humidityMin &&
        tempEntry.value >= tempMinF &&
        tempEntry.value <= tempMaxF
      ) {
        followupWarmHumid++;
      }
    }

    if (followupTotal === 0) continue;

    const followupCoverage = followupWarmHumid / followupTotal;

    // Require at least half the follow-up samples to remain warm/humid.
    if (followupCoverage < 0.5) {
      continue;
    }

    const fieldEntry = {
      value: currTemp.value,
      unit: currTemp.unit || '°F',
      sensorId: currTemp.sensorId || '',
      timestamp: currTemp.timestamp,
      primarySensor: currTemp.primarySensor || false,
    };

    const details = {
      soilMoistureJump: soilJump,
      eventHumidity: currHumidity.value,
      eventTempF: currTemp.value,
      followupCoverage,
      followupWarmHumidCount: followupWarmHumid,
      followupTotalCount: followupTotal,
    };

    return {matched: true, details, fieldEntry};
  }

  return {matched: false};
}

/**
 * Fire notifications for a triggered alert rule.
 *
 * @param {Object} args
 * @param {FirebaseFirestore.DocumentSnapshot} args.ruleDoc
 * @param {Object} args.rule
 * @param {string} args.organizationId
 * @param {string} args.siteId
 * @param {string} args.zoneId
 * @param {Object} args.fieldEntry
 * @param {Date} args.now
 * @param {boolean} [args.isTest=false]
 * @param {Object|null} [args.ruleMatchDetails=null]
 * @return {Promise<{notified: number}>}
 */
async function dispatchAlertNotifications({
  ruleDoc,
  rule,
  organizationId,
  siteId,
  zoneId,
  fieldEntry,
  now,
  isTest = false,
  ruleMatchDetails = null,
}) {
  const prefix = isTest ? '[TEST] ' : '';

  let messageParts;
  if (rule.ruleType === 'frost_warning') {
    messageParts = buildFrostAlertMessage(rule, ruleMatchDetails || {});
  } else if (rule.ruleType === 'mold_risk') {
    messageParts = buildMoldAlertMessage(rule, ruleMatchDetails || {});
  } else if (rule.ruleType === 'black_rot_risk') {
    messageParts = buildBlackRotAlertMessage(rule, ruleMatchDetails || {});
  } else {
    messageParts = buildThresholdAlertMessage(rule, fieldEntry);
  }

  const alertTitle = `${prefix}${messageParts.title}`;
  const alertBody = messageParts.body;

  if (!isTest) {
    await ruleDoc.ref.update({lastFiredAt: FieldValue.serverTimestamp()});

    await bigquery
        .dataset(DATASET_ID)
        .table(ALERTS_TABLE_ID)
        .insert([{
          triggeredAt: now.toISOString(),
          organizationId,
          siteId: siteId || null,
          zoneId: zoneId || null,
          sensorId: fieldEntry.sensorId || null,
          ruleId: ruleDoc.id,
          ruleName: rule.name,
          ruleType: rule.ruleType || 'threshold',
          fieldAlias: rule.fieldAlias || null,
          value: fieldEntry.value,
          threshold: rule.threshold != null ? rule.threshold : null,
          operator: rule.operator != null ? rule.operator : null,
          severity: rule.severity || 'warning',
          unit: fieldEntry.unit || null,
          metadata: ruleMatchDetails ? JSON.stringify(ruleMatchDetails) : null,
        }]);
  }

  const notifyIds = rule.notifyUserIds || [];
  if (rule.inAppEnabled !== false && notifyIds.length > 0) {
    const inAppExpiresHours = rule.inAppExpiresAfterHours || 24;
    const expiresAt = new Date(now.getTime() + inAppExpiresHours * 3600000);
    await Promise.all(
        notifyIds.map((userId) =>
          writeInAppNotification({
            userId,
            organizationId,
            title: alertTitle,
            body: alertBody,
            type: 'alert',
            referenceId: ruleDoc.id,
            expiresAt,
          }),
        ),
    );
  }

  const tokenPairs = await getFcmTokenPairs(notifyIds);
  if (tokenPairs.length === 0) {
    console.log(
        `dispatchAlertNotifications: rule "${rule.name}" triggered but no FCM tokens found`,
    );
    return {notified: notifyIds.length};
  }

  const tokens = tokenPairs.map((p) => p.token);
  const message = {
    notification: {title: alertTitle, body: alertBody},
    data: {
      organizationId,
      siteId: siteId || '',
      zoneId: zoneId || '',
      sensorId: fieldEntry.sensorId || '',
      fieldAlias: rule.fieldAlias || '',
      value: String(fieldEntry.value != null ? fieldEntry.value : ''),
      ruleId: ruleDoc.id,
      ruleType: rule.ruleType || 'threshold',
    },
    tokens,
  };

  try {
    const response = await messaging.sendEachForMulticast(message);
    console.log(
        `dispatchAlertNotifications: sent ${response.successCount} notifications for rule "${rule.name}"`,
        {failureCount: response.failureCount, isTest},
    );

    if (!isTest && response.failureCount > 0) {
      const pruneOps = [];
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
              pruneOps.push(
                  db.doc(`users/${pair.uid}`).update({
                    fcmTokens: FieldValue.arrayRemove(badToken),
                  }),
              );
              const systemExpiry = new Date(now.getTime() + 30 * 24 * 3600000);
              pruneOps.push(
                  writeInAppNotification({
                    userId: pair.uid,
                    organizationId,
                    title: 'Push notifications disabled',
                    body: 'Push notifications were disabled on one of your devices. Re-enable them from Alert Rules.',
                    type: 'system',
                    referenceId: null,
                    expiresAt: systemExpiry,
                  }),
              );
            }
          }
        }
      });

      if (pruneOps.length > 0) {
        await Promise.all(pruneOps);
        console.log('dispatchAlertNotifications: pruned invalid FCM tokens');
      }
    }
  } catch (err) {
    console.error(
        `dispatchAlertNotifications: failed for rule "${rule.name}":`,
        err.message,
    );
  }

  return {notified: notifyIds.length};
}

/**
 * Evaluate all enabled alert rules for the organisation against the freshly
 * ingested sensor readings and send notifications where conditions are met.
 *
 * @param {Object} args
 * @param {string} args.organizationId
 * @param {string} args.siteId
 * @param {string} args.zoneId
 * @param {Array<Object>} args.bqRows
 * @param {Date} args.now
 * @return {Promise<void>}
 */
async function runAlertChecks({organizationId, siteId, zoneId, bqRows, now}) {
  const rulesSnap = await db
      .collection(`organizations/${organizationId}/alertRules`)
      .where('enabled', '==', true)
      .get();

  if (rulesSnap.empty) return;

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

  // Only fetch context if at least one enabled rule of given typeexists.
  const hasFrostRules = rulesSnap.docs.some(
      (doc) => (doc.data().ruleType || 'threshold') === 'frost_warning',
  );
  const hasMoldRules = rulesSnap.docs.some(
      (doc) => (doc.data().ruleType || 'threshold') === 'mold_risk',
  );
  const hasBlackRotRules = rulesSnap.docs.some(
      (doc) => (doc.data().ruleType || 'threshold') === 'black_rot_risk',
  );

  let frostContext = null;
  if (hasFrostRules) {
    try {
      frostContext = await fetchRecentFrostContext({
        organizationId,
        siteId,
        zoneId,
        now,
      });
    } catch (err) {
      console.error('runAlertChecks: failed to fetch frost context:', err.message);
    }
  }

  let moldContext = null;
  if (hasMoldRules) {
    try {
      // Fetch enough history for the common default duration window.
      moldContext = await fetchRecentMoldContext({
        organizationId,
        siteId,
        zoneId,
        now,
        durationHours: 6,
      });
    } catch (err) {
      console.error('runAlertChecks: failed to fetch mold context:', err.message);
    }
  }

  let blackRotContext = null;
  if (hasBlackRotRules) {
    try {
      blackRotContext = await fetchRecentBlackRotContext({
        organizationId,
        siteId,
        zoneId,
        now,
      });
    } catch (err) {
      console.error('runAlertChecks: failed to fetch black rot context:', err.message);
    }
  }

  for (const ruleDoc of rulesSnap.docs) {
    const rule = ruleDoc.data();
    const ruleType = rule.ruleType || 'threshold';

    if (!isWithinActiveDateRange(now, rule.activeRangeStart, rule.activeRangeEnd)) {
      console.log(`checkAlerts: rule "${rule.name}" outside active date range, skipping`);
      continue;
    }

    if (rule.siteId && rule.siteId !== siteId) continue;
    if (rule.zoneId && rule.zoneId !== zoneId) continue;

    if (rule.cooldownMinutes && rule.lastFiredAt) {
      const lastFiredMs = rule.lastFiredAt.toMillis ?
          rule.lastFiredAt.toMillis() :
          Number(rule.lastFiredAt);
      const cooldownMs = rule.cooldownMinutes * 60 * 1000;
      if (now.getTime() - lastFiredMs < cooldownMs) {
        console.log(`checkAlerts: rule "${rule.name}" on cooldown, skipping`);
        continue;
      }
    }

    if (ruleType === 'frost_warning') {
      if (!frostContext) continue;

      const result = evaluateFrostWarning(rule, frostContext);
      if (!result.matched) continue;

      await dispatchAlertNotifications({
        ruleDoc,
        rule,
        organizationId,
        siteId,
        zoneId,
        fieldEntry: result.fieldEntry,
        now,
        isTest: false,
        ruleMatchDetails: result.details,
      });
      continue;
    }

    if (ruleType === 'mold_risk') {
      // Re-fetch if this specific rule wants a longer window than the default fetch.
      const moldDurationHours = defaultIfNull(
          toNumberOrNull((rule.ruleConfig || {}).durationHours),
          6.0,
      );

      let effectiveMoldContext = moldContext;
      if (moldDurationHours > 6) {
        try {
          effectiveMoldContext = await fetchRecentMoldContext({
            organizationId,
            siteId,
            zoneId,
            now,
            durationHours: moldDurationHours,
          });
        } catch (err) {
          console.error('runAlertChecks: failed to refresh mold context:', err.message);
          continue;
        }
      }

      if (!effectiveMoldContext) continue;

      const result = evaluateMoldRisk(rule, effectiveMoldContext);
      if (!result.matched) continue;

      await dispatchAlertNotifications({
        ruleDoc,
        rule,
        organizationId,
        siteId,
        zoneId,
        fieldEntry: result.fieldEntry,
        now,
        isTest: false,
        ruleMatchDetails: result.details,
      });
      continue;
    }

    if (ruleType === 'black_rot_risk') {
      if (!blackRotContext) continue;

      const result = evaluateBlackRotRisk(rule, blackRotContext);
      if (!result.matched) continue;

      await dispatchAlertNotifications({
        ruleDoc,
        rule,
        organizationId,
        siteId,
        zoneId,
        fieldEntry: result.fieldEntry,
        now,
        isTest: false,
        ruleMatchDetails: result.details,
      });
      continue;
    }

    const fieldEntry = fieldValueMap[rule.fieldAlias];
    if (!fieldEntry) continue;

    if (!evaluateAlertCondition(fieldEntry.value, rule.operator, rule.threshold)) {
      continue;
    }

    await dispatchAlertNotifications({
      ruleDoc,
      rule,
      organizationId,
      siteId,
      zoneId,
      fieldEntry,
      now,
      isTest: false,
      ruleMatchDetails: null,
    });
  }
}

module.exports = {
  runAlertChecks,
  dispatchAlertNotifications,
  evaluateFrostWarning,
  fetchRecentFrostContext,
  evaluateMoldRisk,
  fetchRecentMoldContext,
  evaluateBlackRotRisk,
  fetchRecentBlackRotContext,
};
