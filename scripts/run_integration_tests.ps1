# Runs Rolling Alarm integration suites on a connected Android device/emulator.
#
# 1) Screenshot flow (IntegrationTestWidgetsFlutterBinding + PNG export)
# 2) Patrol advanced lifecycle (exact alarm, FSI/lockscreen, snooze/dismiss)
#
# Usage:
#   .\scripts\run_integration_tests.ps1
#   .\scripts\run_integration_tests.ps1 -DeviceId emulator-5554 -SkipPatrol

param(
    [string]$DeviceId = "emulator-5554",
    [switch]$SkipPatrol,
    [switch]$SkipScreenshots
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$devices = adb devices | Select-String -Pattern "device$"
if (-not $devices) {
    Write-Error "No adb device/emulator attached. Start an AVD or plug in a phone, then re-run."
    exit 1
}

Write-Host "Using device: $DeviceId"
& "$PSScriptRoot\adb_grant_exact_alarm.ps1"

$failed = $false

if (-not $SkipScreenshots) {
    Write-Host "`n=== Screenshot integration suite ==="
    & "$PSScriptRoot\run_screenshot_flow.ps1" -DeviceId $DeviceId
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Screenshot suite failed with exit $LASTEXITCODE"
        $failed = $true
    }

    Write-Host "`n=== Screenshot companion suite (interval / FSI ring) ==="
    flutter test integration_test/screenshot_companions_test.dart -d $DeviceId --no-uninstall
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Screenshot companions failed with exit $LASTEXITCODE"
        $failed = $true
    }
}

if (-not $SkipPatrol) {
    Write-Host "`n=== Patrol advanced alarm lifecycle suite ==="
    $patrol = Get-Command patrol -ErrorAction SilentlyContinue
    if (-not $patrol) {
        Write-Host "Activating patrol_cli..."
        dart pub global activate patrol_cli
        $env:Path += ";$env:LOCALAPPDATA\Pub\Cache\bin"
    }
    patrol test -t integration_test/advanced_alarm_lifecycle_test.dart --device $DeviceId
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Patrol suite failed with exit $LASTEXITCODE"
        $failed = $true
    }
}

if ($failed) {
    Write-Error "One or more integration suites failed."
    exit 1
}

Write-Host "`nAll requested integration suites completed successfully."
exit 0
