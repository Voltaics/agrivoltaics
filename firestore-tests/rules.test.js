/**
 * Firestore security rules tests — run against the emulator only, never
 * production. These assert TARGET behavior for the rules rewrite (Phase 3
 * of the Agrivoltaics auth hardening plan) and are expected to FAIL against
 * today's firestore.rules, which is intentionally wide open
 * (`allow read, write: if true`) as an emulator-only placeholder. Passing
 * is what defines "the rules rewrite is done."
 *
 * See README.md for how to run these.
 */

const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {doc, getDoc, setDoc, deleteDoc} = require('firebase/firestore');

const PROJECT_ID = 'agrivoltaics-rules-test';
const ORG_A = 'orgA';
const OWNER_UID = 'ownerUser';
const ADMIN_UID = 'adminUser';
const MEMBER_UID = 'memberUser';
const OUTSIDER_UID = 'outsiderUser';

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(
        path.resolve(__dirname, '../firestore.rules'),
        'utf8',
      ),
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();

  // Seed fixture data with rules disabled — this is test setup, not part
  // of what's under test.
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    await setDoc(doc(db, `organizations/${ORG_A}`), {name: 'Org A'});

    await setDoc(doc(db, `organizations/${ORG_A}/members/${OWNER_UID}`), {
      role: 'owner',
      permissions: {canManageMembers: true, canManageSites: true, canManageSensors: true},
    });
    await setDoc(doc(db, `organizations/${ORG_A}/members/${ADMIN_UID}`), {
      role: 'admin',
      permissions: {canManageMembers: true, canManageSites: true, canManageSensors: true},
    });
    await setDoc(doc(db, `organizations/${ORG_A}/members/${MEMBER_UID}`), {
      role: 'member',
      permissions: {canManageMembers: false, canManageSites: true, canManageSensors: true},
    });
  });
});

describe('org read access', () => {
  test('a member can read their own org', async () => {
    const memberDb = testEnv.authenticatedContext(MEMBER_UID).firestore();
    await assertSucceeds(getDoc(doc(memberDb, `organizations/${ORG_A}`)));
  });

  test('a non-member cannot read the org', async () => {
    const outsiderDb = testEnv.authenticatedContext(OUTSIDER_UID).firestore();
    await assertFails(getDoc(doc(outsiderDb, `organizations/${ORG_A}`)));
  });

  test('an unauthenticated caller cannot read the org', async () => {
    const anonDb = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anonDb, `organizations/${ORG_A}`)));
  });
});

describe('member document writes', () => {
  test('a canManageMembers holder can write a new member doc', async () => {
    const adminDb = testEnv.authenticatedContext(ADMIN_UID).firestore();
    await assertSucceeds(
      setDoc(doc(adminDb, `organizations/${ORG_A}/members/newUser`), {
        role: 'viewer',
        permissions: {canManageMembers: false, canManageSites: false, canManageSensors: false},
      }),
    );
  });

  test('a member without canManageMembers cannot write a member doc', async () => {
    const memberDb = testEnv.authenticatedContext(MEMBER_UID).firestore();
    await assertFails(
      setDoc(doc(memberDb, `organizations/${ORG_A}/members/newUser`), {
        role: 'viewer',
        permissions: {canManageMembers: false, canManageSites: false, canManageSensors: false},
      }),
    );
  });

  test('a non-member cannot write a member doc', async () => {
    const outsiderDb = testEnv.authenticatedContext(OUTSIDER_UID).firestore();
    await assertFails(
      setDoc(doc(outsiderDb, `organizations/${ORG_A}/members/newUser`), {
        role: 'viewer',
        permissions: {canManageMembers: false, canManageSites: false, canManageSensors: false},
      }),
    );
  });
});

describe('owner-only actions', () => {
  test('an owner can delete the organization', async () => {
    const ownerDb = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertSucceeds(deleteDoc(doc(ownerDb, `organizations/${ORG_A}`)));
  });

  test('an admin cannot delete the organization', async () => {
    const adminDb = testEnv.authenticatedContext(ADMIN_UID).firestore();
    await assertFails(deleteDoc(doc(adminDb, `organizations/${ORG_A}`)));
  });

  test('an admin cannot grant themselves owner status', async () => {
    const adminDb = testEnv.authenticatedContext(ADMIN_UID).firestore();
    await assertFails(
      setDoc(
        doc(adminDb, `organizations/${ORG_A}/members/${ADMIN_UID}`),
        {
          role: 'owner',
          permissions: {canManageMembers: true, canManageSites: true, canManageSensors: true},
        },
        {merge: true},
      ),
    );
  });

  test('an owner can revoke another owner\'s status', async () => {
    // Seed a second owner so revoking one doesn't hit the "last owner" guard.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `organizations/${ORG_A}/members/secondOwner`), {
        role: 'owner',
        permissions: {canManageMembers: true, canManageSites: true, canManageSensors: true},
      });
    });

    const ownerDb = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertSucceeds(
      setDoc(
        doc(ownerDb, `organizations/${ORG_A}/members/secondOwner`),
        {
          role: 'admin',
          permissions: {canManageMembers: true, canManageSites: true, canManageSensors: true},
        },
        {merge: true},
      ),
    );
  });
});
