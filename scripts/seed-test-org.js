/**
 * Seeds a test organization (with the given email as owner) directly into
 * the LOCAL Firestore emulator, bypassing both the app's UI and
 * AppConstants.canCreateOrganizationForUser (which only allows one
 * hardcoded account to create orgs through the app itself — see
 * docs/LocalDevSetup.md "Known local-testing limitations").
 *
 * Firebase Auth stays real (matching start-local-dev.ps1's design): this
 * script looks up — or, if they've never signed in before, creates — the
 * given email's real Auth account via the Admin SDK, so that when you sign
 * in with that email through Google Sign-In in the browser afterward, it
 * resolves to the same UID and you land in the org this script just seeded.
 *
 * Usage: node scripts/seed-test-org.js <email> [orgName]
 * Prerequisite: Application Default Credentials for the real Firebase
 * project, e.g. `gcloud auth application-default login` — this is separate
 * from `firebase login`.
 */

const EMULATOR_HOST = '127.0.0.1:8080';
const PROJECT_ID = 'agrivoltaics-flutter-firebase';

// Must be set before the first admin.firestore() call. Only affects
// Firestore — admin.auth() below still talks to the real project.
process.env.FIRESTORE_EMULATOR_HOST = EMULATOR_HOST;

const admin = require('firebase-admin');

async function main() {
  const [, , email, orgNameArg] = process.argv;

  if (!email) {
    console.error('Usage: node scripts/seed-test-org.js <email> [orgName]');
    process.exit(1);
  }

  const normalizedEmail = email.trim().toLowerCase();
  const emailRegex = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
  if (!emailRegex.test(normalizedEmail)) {
    console.error(`"${email}" doesn't look like a valid email address.`);
    process.exit(1);
  }

  const orgName = (orgNameArg && orgNameArg.trim()) ||
    `${normalizedEmail.split('@')[0]}'s Test Org`;

  admin.initializeApp({projectId: PROJECT_ID});

  let uid;
  try {
    const user = await admin.auth().getUserByEmail(normalizedEmail);
    uid = user.uid;
    console.log(`Found existing account for ${normalizedEmail} (uid: ${uid}).`);
  } catch (err) {
    if (err.code !== 'auth/user-not-found') {
      console.error('Could not look up the account. Is Application Default');
      console.error('Credentials set up for the real project? Run:');
      console.error('  gcloud auth application-default login');
      console.error(`\nUnderlying error: ${err.message}`);
      process.exit(1);
    }
    const created = await admin.auth().createUser({email: normalizedEmail});
    uid = created.uid;
    console.log(`No existing account for ${normalizedEmail} — created one (uid: ${uid}).`);
    console.log('Sign in with this email via Google Sign-In in the app; it will');
    console.log('resolve to this same account.');
  }

  // From here on, Firestore calls go to the local emulator (FIRESTORE_EMULATOR_HOST).
  const db = admin.firestore();
  const {Timestamp} = admin.firestore;

  const orgRef = db.collection('organizations').doc();
  const now = Timestamp.now();

  await orgRef.set({
    name: orgName,
    description: 'Seeded locally by scripts/seed-test-org.js.',
    logoUrl: null,
    createdAt: now,
    updatedAt: now,
    createdBy: uid,
  });

  await orgRef.collection('members').doc(uid).set({
    email: normalizedEmail,
    role: 'owner',
    permissions: {canManageMembers: true, canManageSites: true, canManageSensors: true},
    joinedAt: now,
    invitedBy: null,
    lastActive: null,
  });

  console.log('');
  console.log(`Seeded org "${orgName}" (${orgRef.id}) with ${normalizedEmail} as owner.`);
  console.log('Sign into the app with that email and select this org.');
  process.exit(0);
}

main().catch((err) => {
  console.error('Seeding failed:', err.message || err);
  process.exit(1);
});
