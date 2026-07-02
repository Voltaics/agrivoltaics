<#
.SYNOPSIS
Stops the local dev stack started by scripts\start-local-dev.ps1 (Firestore
emulator + Flutter app), including their child processes.
#>

$repoRoot = Split-Path -Parent $PSScriptRoot
$pidFile = Join-Path $repoRoot ".local-dev-pids.json"

if (-not (Test-Path $pidFile)) {
    Write-Host "No running local dev stack found (no $pidFile). Nothing to stop." -ForegroundColor Yellow
    exit 0
}

$state = Get-Content $pidFile | ConvertFrom-Json

$targets = @(
    @{ Name = "Flutter app"; Id = $state.flutterPid },
    @{ Name = "Firestore emulator"; Id = $state.emulatorPid }
)

foreach ($target in $targets) {
    if ($target.Id -and (Get-Process -Id $target.Id -ErrorAction SilentlyContinue)) {
        Write-Host "Stopping $($target.Name) (PID $($target.Id)) and its child processes..." -ForegroundColor Cyan
        # taskkill /T kills the whole process tree (Start-Process only gives us
        # the outer powershell.exe PID; the actual flutter/dart/java/node
        # processes are children of it and won't die from Stop-Process alone).
        taskkill /PID $target.Id /T /F | Out-Null
    } else {
        Write-Host "$($target.Name) already stopped." -ForegroundColor DarkGray
    }
}

Remove-Item $pidFile -Force
Write-Host "Local dev stack stopped." -ForegroundColor Green
