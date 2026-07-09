# Local Dev Setup — Flutter App Against a Local Firestore Emulator

This documents how to set up a Windows machine from scratch to run the Flutter app
(`application/agrivoltaics_flutter_app`) locally against a **disposable local Firestore
database**, so you can freely create/break test orgs, members, and invites without
touching production data. Firebase Auth still uses the real project — you sign in with
a real Google account — only Firestore reads/writes are redirected locally.

This is a one-time setup per machine. Once done, day-to-day use is just
`scripts\start-local-dev.ps1` / `scripts\stop-local-dev.ps1`.

## 1. Prerequisites you probably already have

- **Node.js + npm** (`node --version`, `npm --version`). If missing, install from nodejs.org.
- **Git**.

## 2. Install the Flutter SDK — pinned version, not `stable`

This project's dependency lockfile (`pubspec.lock`) resolves against older transitive
package versions than the current Flutter `stable` channel. If you clone the latest
`stable` branch, `flutter run` will fail to compile with errors like:

```
Error: The class 'IconData' can't be extended outside of its library because it's a final class.
```

This comes from `material_design_icons_flutter` / `font_awesome_flutter` subclassing
`IconData`, which a newer Dart SDK forbids. **Use Flutter 3.38.10** instead (matches
this project's `pubspec.lock` `sdks:` constraint, `flutter: >=3.38.0`):

```powershell
git clone https://github.com/flutter/flutter.git -b 3.38.10 C:\Workspace\UC\Research_Summer2026\flutter
```

(Pick any local path without spaces; adjust the commands below if you use a different one.)

Add it to your **User** PATH permanently:

```powershell
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
[Environment]::SetEnvironmentVariable("PATH", "$userPath;C:\Workspace\UC\Research_Summer2026\flutter\bin", "User")
```

Open a **new** terminal (PATH changes don't apply to already-open shells), then verify:

```powershell
flutter --version
# Should print: Flutter 3.38.10 ...
```

> If a future `pubspec.lock` update raises the `flutter:` floor past 3.38.x, or if you
> hit the `IconData` error again on a newer SDK, check `pubspec.lock`'s `sdks:` block
> and pick a nearby tag with `git checkout <tag>` inside the cloned Flutter repo instead
> of re-cloning.

## 3. Install Java (required by the Firestore emulator)

The Firestore emulator is a Java process; Flutter/Firebase tooling itself doesn't need
Java, but `firebase emulators:start` does.

```powershell
winget install Microsoft.OpenJDK.21 --accept-package-agreements --accept-source-agreements
```

Add it to your **User** PATH permanently (adjust the version folder name if different):

```powershell
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
[Environment]::SetEnvironmentVariable("PATH", "$userPath;C:\Program Files\Microsoft\jdk-21.0.11.10-hotspot\bin", "User")
```

Open a **new** terminal and verify: `java -version`.

## 4. Enable Windows Developer Mode

Flutter's build tooling needs symlink support, which Windows only allows without
admin elevation when Developer Mode is on.

```powershell
start ms-settings:developers
```

Toggle **Developer Mode** on in the window that opens.

## 5. Install project dependencies

From the **repo root** (this installs the Firebase CLI locally into `node_modules` —
deliberately *not* global, so it's version-pinned per-project):

```powershell
npm install
```

From the **Flutter app directory**:

```powershell
cd application\agrivoltaics_flutter_app
flutter pub get
```

## 6. Verify everything

```powershell
cd application\agrivoltaics_flutter_app
flutter analyze   # should show only pre-existing lint notes, no errors
flutter doctor -v # Chrome may be missing — that's fine, we use Edge; Android/Windows-desktop toolchain warnings are irrelevant, we only target web
```

Flutter should list **Edge (web)** as a connected device even without Chrome installed —
this app's Google Sign-In currently only implements the web flow anyway
(`lib/auth.dart`'s native-mobile path is commented out), so Edge/Chrome is the only
practical way to run it locally.

## 7. Running the local stack day-to-day

Once the above is done once, use the scripts:

```powershell
# Start (prompts for which email(s) to authorize, e.g. your own Google account)
scripts\start-local-dev.ps1

# or non-interactively:
scripts\start-local-dev.ps1 -AuthorizedEmails "you@gmail.com,teammate@gmail.com"

# or with a test org auto-seeded and owned by you (see "Seeding a test org" below):
scripts\start-local-dev.ps1 you@gmail.com "My Test Org"
```

This opens two windows:
- **Firestore emulator** — data browser/editor at http://127.0.0.1:4000
- **Flutter app** — launches in Edge automatically; this window supports Flutter's
  normal hot-reload keys (`r` = hot reload, `R` = hot restart, `q` = quit)

Sign in with a real Google account whose email you passed to `-AuthorizedEmails`. All
Firestore reads/writes go to the local emulator; nothing touches production.

When done:

```powershell
scripts\stop-local-dev.ps1
```

This kills both windows and their child processes cleanly. Restarting the emulator
always starts from an **empty** database — nothing persists between runs.

## 8. Seeding a test org (working around the hardcoded org-creation gate)

`AppConstants.canCreateOrganizationForUser` in `lib/app_constants.dart` only allows a
single specific UID/email to create organizations through the app's own UI. This is a
hardcoded check, not driven by Firestore data or dart-defines, so it can't be worked
around via `AUTHORIZED_EMAILS` or emulator data alone.

`start-local-dev.ps1` can seed a test org for you instead, bypassing that gate entirely
(it writes straight to the local emulator, not through the app):

```powershell
scripts\start-local-dev.ps1 <your-email> ["Org Name"]
```

This requires credentials for the real project (separate from `firebase login`). Two
ways to get them — **use the service account key** unless you have a specific reason
not to; it's simpler and doesn't depend on your personal Google account's IAM
permissions on the GCP project (which may not be set up even if you can see the
project fine in the Firebase console).

**Option A — service account key (recommended), one-time setup:**

1. Firebase Console → **agrivoltaics-flutter-firebase** → gear icon → **Project
   Settings** → **Service Accounts** tab → **Generate new private key**.
2. Save the downloaded file as `secrets/agrivoltaics-admin-key.json` in this repo.
   That folder is gitignored (see `secrets/README.md`) — the key never gets committed.
3. Before running the script, in the same terminal:
   ```powershell
   $env:GOOGLE_APPLICATION_CREDENTIALS = "secrets\agrivoltaics-admin-key.json"
   ```
   (Set this once per terminal session — it doesn't persist across terminals unless
   you add it to your PowerShell profile.)

This key is a real, long-lived credential with broad Admin SDK access — treat it like
a password. If you ever suspect it leaked, revoke it from the same Service Accounts
page and generate a new one.

**Option B — Application Default Credentials via gcloud**, if you'd rather not
download a key file. *Not* an npm package (`npx gcloud ...` won't work — it's the
standalone Google Cloud SDK CLI):

```powershell
winget install Google.CloudSDK --accept-package-agreements --accept-source-agreements
```

Open a **new** terminal, then:

```powershell
gcloud auth application-default login
```

This can fail with a `PERMISSION_DENIED` / `USER_PROJECT_DENIED` error if your personal
Google account isn't granted the `serviceusage.serviceUsageConsumer` role (or broader)
on the `agrivoltaics-flutter-firebase` GCP project — the error message includes a
console link to grant it. If you hit that, Option A avoids the issue entirely.

What it does: looks up your email's real Firebase Auth account (creates one via the
Admin SDK if you've never signed in before — Auth stays real per this doc's design,
only Firestore is emulated), then seeds an `organizations/{id}` doc plus an owner
`members/{uid}` doc for that account directly into the local emulator. Sign in with
that same email in the browser and you'll land in the seeded org.

If seeding fails (e.g. ADC not set up), the script warns and still starts the app — you
can retry standalone with `node scripts\seed-test-org.js <email> ["Org Name"]` once
the emulator is running, no restart needed. The old manual-edit-and-revert workaround
(temporarily editing `canCreateOrganizationForUser`) still works too if you'd rather do
that for some reason, but shouldn't be necessary anymore.

## 9. Other known local-testing limitations

- **Testing a second "pending member"** (an authorized email that hasn't joined any org)
  requires either a second real Google account signed into a separate browser profile/
  incognito window (simplest, and what we did to verify this), or manually creating a
  `users/{fakeUid}` document in the Emulator UI with the right `email` field.
- The emulator UI lets you inspect/edit any document directly — useful for seeding edge
  cases without going through the app's UI at all.

## 10. Known pre-existing issue you may hit

`OrganizationService.createOrganization()` didn't originally write an `email` field onto
the creating owner's own membership document (only the invite-based `addMember()` path
did) — this was fixed in code, but **existing production organizations created before
the fix may still be missing that field** on their owner's membership doc, which would
make them undercounted in anything that queries membership by email (e.g. the Member
Directory page). A one-time production backfill may be worth doing separately.
