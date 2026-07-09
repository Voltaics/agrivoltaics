# Firestore rules tests

Tests the repo's `firestore.rules` against the Firestore emulator only — never production. These assert the **target** behavior for the Phase 3 rules rewrite (see the architecture audit artifact) and are expected to **fail** against today's rules, which are intentionally wide open (`allow read, write: if true`) as an emulator-only placeholder documented in `firestore.rules` itself. Getting these passing is what defines the rules rewrite as done.

## Run

```bash
cd firestore-tests
npm install
npm test
```

This starts the Firestore emulator (via `firebase emulators:exec`, using the port configured in the repo root's `firebase.json`), loads `../firestore.rules` into it, runs the Jest suite in `rules.test.js`, then tears the emulator down. Requires a JDK (the Firestore emulator runs on the JVM) and the `firebase` CLI to be resolvable — either install `firebase-tools` globally, or run via `npx firebase-tools emulators:exec ...` if you'd rather not.

## What's covered

- **Org read access**: a member can read their own org; a non-member or unauthenticated caller cannot.
- **Member document writes**: only a member with the `canManageMembers` permission can write new member docs.
- **Owner-only actions**: only an owner can delete the organization or grant/revoke another member's owner status — an admin (who can manage members generally) is denied both.

## Adding more cases

Follow the existing fixture in `rules.test.js`'s `beforeEach` (one org, one owner/admin/member) — add fixture docs via `testEnv.withSecurityRulesDisabled(...)`, then assert against `testEnv.authenticatedContext(uid).firestore()` with `assertSucceeds`/`assertFails`. Sites, zones, sensors, alert rules, and frost settings aren't covered yet — worth adding once the client-side membership checks (Phase 1 fixes) have equivalent rules to test against.
