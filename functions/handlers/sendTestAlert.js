/**
 * sendTestAlert — HTTP Cloud Function to fire a test notification for a
 * specific alert rule without needing a real sensor reading.
 *
 * Uses the exact same dispatchAlertNotifications() function as production.
 * The only differences from a real trigger are:
 *  - A synthetic fieldEntry is constructed (no actual sensor reading needed)
 *  - Title is prefixed with "[TEST]"
 *  - No `alerts` document is written
 *  - `lastFiredAt` is not updated (cooldown is not consumed)
 *
 * POST body: { orgId: string, ruleId: string }
 * Auth: Bearer <Firebase ID token> in Authorization header.
 */

const functions = require('firebase-functions');
const {getAuth} = require('firebase-admin/auth');
const {db} = require('../lib/firebase');
const {dispatchAlertNotifications} = require('../lib/alertHelpers');

/**
 * Build a synthetic fieldEntry whose value satisfies the rule's condition.
 * This ensures the same title/body format as a real alert would produce.
 * @param {Object} rule - The alert rule object containing threshold, operator, and unit.
 * @return {Object} A synthetic field entry object with value, unit, sensorId, timestamp, and primarySensor.
 */
function buildTestFieldEntry(rule) {
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

exports.sendTestAlert = functions.https.onRequest(async (req, res) => {
  // CORS pre-flight
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Headers', 'Authorization,Content-Type');
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Verify Firebase auth
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

  // Load the rule
  const ruleDoc = await db
      .doc(`organizations/${orgId}/alertRules/${ruleId}`)
      .get();
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

  // Delegate entirely to the shared production dispatcher with isTest=true
  const {notified} = await dispatchAlertNotifications({
    ruleDoc,
    rule,
    organizationId: orgId,
    siteId: rule.siteId || '',
    zoneId: rule.zoneId || '',
    fieldEntry: buildTestFieldEntry(rule),
    now: new Date(),
    isTest: true,
  });

  res.json({ok: true, notified});
});
