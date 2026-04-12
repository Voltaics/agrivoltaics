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
 * Build a synthetic fieldEntry for threshold rules.
 * @param {Object} rule
 * @return {Object}
 */
function buildThresholdTestFieldEntry(rule) {
  const threshold = rule.threshold || 0;
  let value;
  switch (rule.operator) {
    case 'gt': value = threshold + 1; break;
    case 'gte': value = threshold; break;
    case 'lt': value = threshold - 1; break;
    case 'lte': value = threshold; break;
    case 'eq': value = threshold; break;
    default: value = threshold;
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
  const config = rule.frostConfig || {};

  const airTempF = Number(config.airTempMaxF != null ? config.airTempMaxF : 39.0) - 1;
  const humidity = Number(config.humidityMin != null ? config.humidityMin : 90.0) + 2;
  const soilTempF = Number(config.soilTempMaxF != null ? config.soilTempMaxF : 45.0) - 1;
  const light = Number(config.lightMax != null ? config.lightMax : 5000.0);
  const tempDropRateFPerHour = Number(config.tempDropRateFPerHour != null ? config.tempDropRateFPerHour : 2.0) + 0.5;

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

  const authHeader = req.headers['authorization'] || '';
  const idToken = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
  if (!idToken) {
    res.status(401).json({error: 'Missing auth token'});
    return;
  }

  try {
    await getAuth().verifyIdToken(idToken);
  } catch (_) {
    res.status(401).json({error: 'Invalid auth token'});
    return;
  }

  const {orgId, ruleId} = req.body;
  if (!orgId || !ruleId) {
    res.status(400).json({error: 'orgId and ruleId are required'});
    return;
  }

  const ruleDoc = await db.doc(`organizations/${orgId}/alertRules/${ruleId}`).get();
  if (!ruleDoc.exists) {
    res.status(404).json({error: 'Rule not found'});
    return;
  }

  const rule = ruleDoc.data();
  const notifyIds = rule.notifyUserIds || [];
  if (notifyIds.length === 0) {
    res.json({ok: true, notified: 0, message: 'No subscribers on this rule'});
    return;
  }

  const ruleType = rule.ruleType || 'threshold';

  let fieldEntry;
  let ruleMatchDetails = null;

  if (ruleType === 'frost_warning') {
    const frostPayload = buildFrostWarningTestPayload(rule);
    fieldEntry = frostPayload.fieldEntry;
    ruleMatchDetails = frostPayload.details;
  } else {
    fieldEntry = buildThresholdTestFieldEntry(rule);
  }

  const {notified} = await dispatchAlertNotifications({
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

  res.json({ok: true, notified});
});
