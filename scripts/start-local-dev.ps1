<#
.SYNOPSIS
Starts the local dev stack for agrivoltaics_flutter_app: a local Firestore
emulator plus the Flutter web app (Edge), with the app's Firestore reads/
writes redirected to that emulator. Firebase Auth still uses the real
project, so you sign in with a real Google account - only Firestore data is
local and disposable.

One-time environment setup (Flutter, Java, Developer Mode, etc.) is NOT done
by this script - see docs/LocalDevSetup.md first if you haven't done that yet.

.PARAMETER AuthorizedEmails
Comma-separated email(s) to authorize for local sign-in (e.g. your own
Google account). If omitted, you'll be prompted, or set
$env:LOCAL_DEV_AUTHORIZED_EMAILS to skip the prompt.

.EXAMPLE
scripts\start-local-dev.ps1 -AuthorizedEmails "you@gmail.com"
#>

param(
    [string]$AuthorizedEmails
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $repoRoot "application\agrivoltaics_flutter_app"
$pidFile = Join-Path $repoRoot ".local-dev-pids.json"

# --- Preflight: make sure the one-time setup has been done ---
foreach ($cmd in @("flutter", "java")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error "'$cmd' not found on PATH. Follow docs/LocalDevSetup.md to install it first."
        exit 1
    }
}

if (-not (Test-Path (Join-Path $repoRoot "node_modules\.bin\firebase.cmd"))) {
    Write-Error "Firebase CLI not found in node_modules. Run 'npm install' at the repo root first (see docs/LocalDevSetup.md)."
    exit 1
}

if (Test-Path $pidFile) {
    Write-Warning "A local dev stack already looks like it's running (found $pidFile)."
    Write-Warning "Run scripts\stop-local-dev.ps1 first if you want a clean restart."
    exit 1
}

# --- Resolve which email(s) to authorize ---
if (-not $AuthorizedEmails) {
    $AuthorizedEmails = $env:LOCAL_DEV_AUTHORIZED_EMAILS
}
if (-not $AuthorizedEmails) {
    $AuthorizedEmails = Read-Host "Enter comma-separated email(s) to authorize for local sign-in (e.g. your Google account)"
}
if (-not $AuthorizedEmails) {
    Write-Error "No authorized email(s) provided - you won't be able to sign in. Aborting."
    exit 1
}

# --- Start the Firestore emulator in its own window ---
Write-Host "Starting Firestore emulator..." -ForegroundColor Cyan
$emulatorProc = Start-Process powershell -WorkingDirectory $repoRoot -ArgumentList @(
    "-NoExit", "-Command",
    "npx firebase emulators:start --only firestore --config firebase.emulator.json"
) -PassThru -WindowStyle Normal

Write-Host "Waiting for the emulator to come up on 127.0.0.1:8080..." -ForegroundColor Cyan
$maxWaitSeconds = 60
$waited = 0
$ready = $false
while ($waited -lt $maxWaitSeconds) {
    $ready = Test-NetConnection -ComputerName 127.0.0.1 -Port 8080 -WarningAction SilentlyContinue -InformationLevel Quiet
    if ($ready) { break }
    Start-Sleep -Seconds 1
    $waited++
}
if (-not $ready) {
    Write-Error "Firestore emulator did not come up within $maxWaitSeconds seconds - check its window for errors (it may still be downloading on first run)."
    exit 1
}
Write-Host "Firestore emulator ready. Emulator UI: http://127.0.0.1:4000" -ForegroundColor Green

# --- Start the Flutter app in its own window (interactive, for hot reload) ---
Write-Host "Starting Flutter app in Edge (authorized: $AuthorizedEmails)..." -ForegroundColor Cyan
$flutterProc = Start-Process powershell -WorkingDirectory $appDir -ArgumentList @(
    "-NoExit", "-Command",
    "flutter run -d edge --dart-define=USE_FIRESTORE_EMULATOR=true --dart-define=`"AUTHORIZED_EMAILS=$AuthorizedEmails`""
) -PassThru -WindowStyle Normal

@{
    emulatorPid = $emulatorProc.Id
    flutterPid  = $flutterProc.Id
    startedAt   = (Get-Date).ToString("o")
} | ConvertTo-Json | Set-Content -Path $pidFile

Write-Host ""
Write-Host "Local dev stack starting in two new windows:" -ForegroundColor Green
Write-Host "  - Firestore emulator (PID $($emulatorProc.Id)) - data browser at http://127.0.0.1:4000"
Write-Host "  - Flutter app (PID $($flutterProc.Id)) - Edge opens automatically; that window supports hot reload ('r')"
Write-Host ""
Write-Host "Run scripts\stop-local-dev.ps1 when you're done." -ForegroundColor Yellow
