/**
 * Shared HTTP request helpers for Cloud Functions handlers: CORS/method
 * guarding, Firebase ID token verification, and org-membership/admin checks.
 *
 * Each handler still writes its own response body (shapes differ across
 * handlers today), these helpers only do the verification work so it isn't
 * copy-pasted (or silently skipped) per handler.
 */

const {getAuth} = require('firebase-admin/auth');
const {db} = require('./firebase');

/**
 * Applies CORS headers and handles the OPTIONS preflight / non-POST guard.
 *
 * @param {Object} req - Express request object.
 * @param {Object} res - Express response object.
 * @param {Object} [opts] - Options.
 * @param {string} [opts.methods] - Access-Control-Allow-Methods value.
 * @return {boolean} True if the request was fully handled (caller should
 *   return immediately without further processing).
 */
function handlePreflightAndMethod(req, res, opts = {}) {
  const methods = opts.methods || 'POST, OPTIONS';

  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', methods);
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return true;
  }

  if (req.method !== 'POST') {
    res.status(405).json({
      success: false,
      error: 'Method Not Allowed. Use POST.',
    });
    return true;
  }

  return false;
}

/**
 * Verifies the `Authorization: Bearer <idToken>` header.
 *
 * @param {Object} req - Express request object.
 * @return {Promise<Object|null>} Decoded token, or null if the header is
 *   missing/invalid/expired.
 */
async function verifyAuthHeader(req) {
  const authHeader = req.headers.authorization || '';
  const match = authHeader.match(/^Bearer (.+)$/);

  if (!match) {
    return null;
  }

  try {
    return await getAuth().verifyIdToken(match[1]);
  } catch (err) {
    return null;
  }
}

/**
 * Checks whether uid is a member of organizationId, per
 * organizations/{organizationId}/members/{uid}.
 *
 * @param {string} organizationId - Organization ID.
 * @param {string} uid - Firebase Auth UID.
 * @return {Promise<boolean>} True if a membership doc exists for this user.
 */
async function isOrgMember(organizationId, uid) {
  const memberDoc = await db.doc(`organizations/${organizationId}/members/${uid}`).get();
  return memberDoc.exists;
}

// Admin allowlist for endpoints that aren't org-scoped (e.g. one-time infra
// setup). Kept in sync by hand with organizationCreationAllowedUid in
// application/agrivoltaics_flutter_app/lib/app_constants.dart — add your own
// UID here (Firebase Console → Authentication) before calling admin-only
// endpoints if you're not already on this list.
const ADMIN_UIDS = new Set([
  '2qeg0hRKEPbJX4mIwtjZcsEVWFx2',
]);

/**
 * @param {string} uid - Firebase Auth UID.
 * @return {boolean} True if uid is on the admin allowlist.
 */
function isAdmin(uid) {
  return ADMIN_UIDS.has(uid);
}

module.exports = {
  handlePreflightAndMethod,
  verifyAuthHeader,
  isOrgMember,
  isAdmin,
};
