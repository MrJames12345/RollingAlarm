# Runs the screenshot integration suite on a connected device, then pulls PNGs
# into the repository screenshots/ folder.
#
# Device writes land in app scoped storage. flutter test may clear that data
# when the package is reinstalled or torn down, so a delayed poller pulls via
# run-as only after valid PNG signatures are present.
#
# Usage: .\scripts\run_screenshot_flow.ps1 [-DeviceId emulator-5554]

param(
    [string]$DeviceId = "emulator-5554"
)

$ErrorActionPreference = "Continue"
$repoRoot = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $repoRoot "screenshots"
$package = "com.example.rolling_alarm"
Set-Location $repoRoot

New-Item -ItemType Directory -Force -Path $dest | Out-Null

$names = @(
    "01_home_screen.png",
    "02_routine_edit_screen.png",
    "03_active_countdown.png",
    "04_alarm_ring_screen.png",
    "05_logs_screen.png"
)

function Test-ValidPng([string]$path) {
    if (-not (Test-Path $path)) { return $false }
    $item = Get-Item $path
    if ($item.Length -le 64) { return $false }
    $bytes = [System.IO.File]::ReadAllBytes($path)[0..7]
    return ($bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47)
}

Write-Host "Installing debug APK on $DeviceId (builds if needed)..."
flutter build apk --debug
adb -s $DeviceId install -r "build\app\outputs\flutter-apk\app-debug.apk"

Write-Host "Granting alarm related appops..."
& "$PSScriptRoot\adb_grant_exact_alarm.ps1"

# flutter test reinstalls the APK and can wipe appops. Keep re-granting in the
# background until the Dart suite finishes.
$grantJob = Start-Job -ArgumentList $DeviceId -ScriptBlock {
    param($DeviceId)
    $pkg = "com.example.rolling_alarm"
    for ($i = 0; $i -lt 240; $i++) {
        adb -s $DeviceId shell cmd appops set $pkg SCHEDULE_EXACT_ALARM allow 2>$null | Out-Null
        adb -s $DeviceId shell pm grant $pkg android.permission.POST_NOTIFICATIONS 2>$null | Out-Null
        adb -s $DeviceId shell cmd appops set $pkg USE_FULL_SCREEN_INTENT allow 2>$null | Out-Null
        Start-Sleep -Seconds 2
    }
}

$poller = Start-Job -ArgumentList $DeviceId, $package, $dest, $names -ScriptBlock {
    param($DeviceId, $package, $dest, $names)
    function Test-ValidPng([string]$path) {
        if (-not (Test-Path $path)) { return $false }
        $item = Get-Item $path
        if ($item.Length -le 64) { return $false }
        $bytes = [System.IO.File]::ReadAllBytes($path)[0..7]
        return ($bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47)
    }
    # Allow flutter test to rebuild/reinstall before polling.
    Start-Sleep -Seconds 45
    for ($i = 0; $i -lt 180; $i++) {
        $tmpDir = Join-Path $env:TEMP "ra_shot_pull"
        New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
        $ok = 0
        foreach ($name in $names) {
            $tmp = Join-Path $tmpDir $name
            cmd /c "adb -s $DeviceId exec-out run-as $package cat app_flutter/screenshots/$name > `"$tmp`" 2>nul"
            if (Test-ValidPng $tmp) {
                Copy-Item $tmp (Join-Path $dest $name) -Force
                $ok++
            }
        }
        if ($ok -eq $names.Count) {
            "PULLED_OK"
            return
        }
        Start-Sleep -Seconds 2
    }
    "PULLED_TIMEOUT"
}

Write-Host "Running screenshot_flow_test.dart on $DeviceId ..."
# --no-uninstall keeps app data (and just-written PNGs) available for pull, and
# avoids DELETE_FAILED_INTERNAL_ERROR flake on some API 34 AVDs.
flutter test integration_test/screenshot_flow_test.dart -d $DeviceId --no-uninstall
$testExit = $LASTEXITCODE

Stop-Job $grantJob -ErrorAction SilentlyContinue
Remove-Job $grantJob -Force -ErrorAction SilentlyContinue

# Re-grant is useful if flutter reinstalled the package mid-run.
& "$PSScriptRoot\adb_grant_exact_alarm.ps1" 2>$null

Write-Host "Waiting for screenshot poller..."
$null = Wait-Job $poller -Timeout 90
$pollResult = Receive-Job $poller
Remove-Job $poller -Force -ErrorAction SilentlyContinue
Write-Host "Poller result: $pollResult"

$stillMissing = @($names | Where-Object { -not (Test-ValidPng (Join-Path $dest $_)) })
if ($stillMissing.Count -gt 0) {
    Write-Host "Fallback pull via scripts/pull_screenshots.ps1 ..."
    & "$PSScriptRoot\pull_screenshots.ps1"
    $stillMissing = @($names | Where-Object { -not (Test-ValidPng (Join-Path $dest $_)) })
}

if ($testExit -ne 0) {
    Write-Error "Integration test exited with code $testExit"
    exit $testExit
}
if ($stillMissing.Count -gt 0) {
    Write-Error ("Missing expected PNGs in repo: " + ($stillMissing -join ", "))
    exit 1
}

Write-Host "Screenshot flow complete. PNGs in $dest"
Get-ChildItem $dest -Filter "*.png" | ForEach-Object {
    Write-Host " - $($_.Name) ($($_.Length) bytes)"
}
exit 0
