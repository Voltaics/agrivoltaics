/**
 * sendTestAlert — HTTP Cloud Function to fire a test notification for a
 * specific alert rule without needing a real sensor reading.
 *
 * POST body: { orgId: string, ruleId: string }
 * Auth: Bearer <Firebase ID token> in Authorization header.
 */

const functions = require('firebase-functions');
const {getAuth} = require('firebase-admin/auth');
const {db} = require('../lib/firebase');
const {
  dispatchAlertNotifications,
} = require('../lib/alertHelpers');

/**
 * Return value unless it is null/undefined, else fallback.
 * @param {*} value
 * @param {*} fallback
 * @return {*}
 */
function defaultIfNull(value, fallback) {
  return value != null ? value : fallback;
}

/**
 * Build a synthetic fieldEntry for threshold rules.
 * @param {Object} rule
 * @return {Object}
 */
function buildThresholdTestFieldEntry(rule) {
  const threshold = rule.threshold != null ? Number(rule.threshold) : 0;
  let value;

  switch (rule.operator) {
    case 'gt':
      value = threshold + 1;
      break;
    case 'gte':
      value = threshold;
      break;
    case 'lt':
      value = threshold - 1;
      break;
    case 'lte':
      value = threshold;
      break;
    case 'eq':
      value = threshold;
      break;
    default:
      value = threshold;
      break;
  }

  return {
    value,
    unit: rule.unit || '',
    sensorId: 'test',
    timestamp: new Date().toISOString(),
    primarySensor: false,
  };
}

/**
 * Build a synthetic frost warning test payload.
 * @param {Object} rule
 * @return {{fieldEntry: Object, details: Object}}
 */
function buildFrostWarningTestPayload(rule) {
  const config = rule.ruleConfig || rule.frostConfig || {};

  const airTempF = Number(defaultIfNull(config.airTempMaxF, 39.0)) - 1;
  const humidity = Number(defaultIfNull(config.humidityMin, 90.0)) + 2;
  const soilTempF = Number(defaultIfNull(config.soilTempMaxF, 45.0)) - 1;
  const light = Number(defaultIfNull(config.lightMax, 5.0));
  const tempDropRateFPerHour =
    Number(defaultIfNull(config.tempDropRateFPerHour, 2.0)) + 0.5;

  const anticipateSkyClearingDuringNight =
    config.anticipateSkyClearingDuringNight === true;

  return {
    fieldEntry: {
      value: airTempF,
      unit: '°F',
      sensorId: 'test',
      timestamp: new Date().toISOString(),
      primarySensor: false,
    },
    details: {
      airTempF,
      humidity,
      soilTempF,
      light,
      tempDropRateFPerHour,
      anticipateSkyClearingDuringNight,
      preSunsetLuxDropRate: anticipateSkyClearingDuringNight ? null : 1500.0,
      clearingLuxDropRatePerHourMin: 1000.0,
    },
  };
}

/**
 * Build a synthetic mold risk test payload.
 * @param {Object} rule
 * @return {{fieldEntry: Object, details: Object}}
 */
function buildMoldRiskTestPayload(rule) {
  const config = rule.ruleConfig || {};

  const humidityMin = Number(defaultIfNull(config.humidityMin, 85.0));
  const tempMinF = Number(defaultIfNull(config.tempMinF, 68.0));
  const tempMaxF = Number(defaultIfNull(config.tempMaxF, 86.0));
  const lightMax = Number(defaultIfNull(config.lightMax, 5.0));
  const soilMoistureMin = Number(defaultIfNull(config.soilMoistureMin, 40.0));
  const durationHours = Number(defaultIfNull(config.durationHours, 6.0));

  const avgTempF = (tempMinF + tempMaxF) / 2.0;
  const avgHumidity = humidityMin + 3.0;
  const avgLight = lightMax;
  const avgSoilMoisture = soilMoistureMin + 2.0;
  const qualifyingHours = durationHours + 0.5;

  return {
    fieldEntry: {
      value: avgTempF,
      unit: '°F',
      sensorId: 'test',
      timestamp: new Date().toISOString(),
      primarySensor: false,
    },
    details: {
      qualifyingHours,
      avgHumidity,
      avgTempF,
      avgLight,
      avgSoilMoisture,
    },
  };
}

/**
 * Build a synthetic black rot risk test payload.
 * @param {Object} rule
 * @return {{fieldEntry: Object, details: Object}}
 */
function buildBlackRotRiskTestPayload(rule) {
  const config = rule.ruleConfig || {};

  const humidityMin = Number(defaultIfNull(config.humidityMin, 90.0));
  const tempMinF = Number(defaultIfNull(config.tempMinF, 70.0));
  const tempMaxF = Number(defaultIfNull(config.tempMaxF, 85.0));
  const soilMoistureJump = Number(defaultIfNull(config.soilMoistureJump, 8.0));

  const eventTempF = (tempMinF + tempMaxF) / 2.0;
  const eventHumidity = humidityMin + 2.0;
  const followupCoverage = 0.75;

  return {
    fieldEntry: {
      value: eventTempF,
      unit: '°F',
      sensorId: 'test',
      timestamp: new Date().toISOString(),
      primarySensor: false,
    },
    details: {
      soilMoistureJump: soilMoistureJump + 1.0,
      eventHumidity,
      eventTempF,
      followupCoverage,
      followupWarmHumidCount: 9,
      followupTotalCount: 12,
    },
  };
}

exports.sendTestAlert = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Headers', 'Authorization,Content-Type');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  const authHeader = req.headers.authorization || '';
  const idToken = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;

  if (!idToken) {
    res.status(401).json({error: 'Missing auth token'});
    return;
  }

  try {
    await getAuth().verifyIdToken(idToken);
  } catch (err) {
    res.status(401).json({error: 'Invalid auth token'});
    return;
  }

  const orgId = req.body && req.body.orgId;
  const ruleId = req.body && req.body.ruleId;

  if (!orgId || !ruleId) {
    res.status(400).json({error: 'orgId and ruleId are required'});
    return;
  }

  try {
    const ruleDoc = await db.doc(`organizations/${orgId}/alertRules/${ruleId}`).get();

    if (!ruleDoc.exists) {
      res.status(404).json({error: 'Rule not found'});
      return;
    }

    const rule = ruleDoc.data();
    const notifyIds = Array.isArray(rule.notifyUserIds) ? rule.notifyUserIds : [];

    if (notifyIds.length === 0) {
      res.json({
        ok: true,
        notified: 0,
        message: 'No subscribers on this rule',
      });
      return;
    }

    const ruleType = rule.ruleType || 'threshold';

    let fieldEntry;
    let ruleMatchDetails = null;

    if (ruleType === 'frost_warning') {
      const frostPayload = buildFrostWarningTestPayload(rule);
      fieldEntry = frostPayload.fieldEntry;
      ruleMatchDetails = frostPayload.details;
    } else if (ruleType === 'mold_risk') {
      const moldPayload = buildMoldRiskTestPayload(rule);
      fieldEntry = moldPayload.fieldEntry;
      ruleMatchDetails = moldPayload.details;
    } else if (ruleType === 'black_rot_risk') {
      const blackRotPayload = buildBlackRotRiskTestPayload(rule);
      fieldEntry = blackRotPayload.fieldEntry;
      ruleMatchDetails = blackRotPayload.details;
    } else {
      fieldEntry = buildThresholdTestFieldEntry(rule);
    }

    const result = await dispatchAlertNotifications({
      ruleDoc,
      rule,
      organizationId: orgId,
      siteId: rule.siteId || '',
      zoneId: rule.zoneId || '',
      fieldEntry,
      now: new Date(),
      isTest: true,
      ruleMatchDetails,
    });

    res.json({
      ok: true,
      notified: result && result.notified != null ? result.notified : 0,
      ruleType,
    });
  } catch (err) {
    console.error('sendTestAlert failed:', err.message || err);
    res.status(500).json({
      error: 'Failed to send test alert',
      details: err.message || String(err),
    });
  }
});
