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

## 8. Known local-testing limitations

- **Org creation is gated to one hardcoded account.** `AppConstants.canCreateOrganizationForUser`
  in `lib/app_constants.dart` only allows a single specific UID/email to create
  organizations. This is a hardcoded check, not driven by Firestore data or dart-defines,
  so it can't be worked around via `AUTHORIZED_EMAILS` or emulator data alone. To create
  a test org locally as a different account, temporarily edit that function to also
  allow your email, test, then **revert the file** (`git checkout -- lib/app_constants.dart`)
  before committing anything — do not leave a debug bypass in place.
- **Testing a second "pending member"** (an authorized email that hasn't joined any org)
  requires either a second real Google account signed into a separate browser profile/
  incognito window (simplest, and what we did to verify this), or manually creating a
  `users/{fakeUid}` document in the Emulator UI with the right `email` field.
- The emulator UI lets you inspect/edit any document directly — useful for seeding edge
  cases without going through the app's UI at all.

## 9. Known pre-existing issue you may hit

`OrganizationService.createOrganization()` didn't originally write an `email` field onto
the creating owner's own membership document (only the invite-based `addMember()` path
did) — this was fixed in code, but **existing production organizations created before
the fix may still be missing that field** on their owner's membership doc, which would
make them undercounted in anything that queries membership by email (e.g. the Member
Directory page). A one-time production backfill may be worth doing separately.
