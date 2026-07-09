# secrets/

Local-only credentials that must never be committed. Everything in this
folder except this README is gitignored (see the repo root `.gitignore`).

## What goes here

Service account key JSON files downloaded from Firebase Console → Project
Settings → Service Accounts → **Generate new private key**, used to give
`scripts/seed-test-org.js` (and `start-local-dev.ps1`, which calls it)
permission to look up/create your real Firebase Auth account for local
testing. See `docs/LocalDevSetup.md` section 8.

Suggested filename: `agrivoltaics-admin-key.json`.

## Usage

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS = "secrets\agrivoltaics-admin-key.json"
scripts\start-local-dev.ps1 <your-email> ["Org Name"]
```

## If you ever suspect a key here leaked

Revoke it immediately in Firebase Console → Project Settings → Service
Accounts → the key's row → delete, then generate a new one. Downloaded keys
are long-lived credentials with broad Admin SDK access — treat one like a
password, not a config file.
