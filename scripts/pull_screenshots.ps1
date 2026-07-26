# Pulls instrumentation screenshots from the device into repo screenshots/.
# Usage: .\scripts\pull_screenshots.ps1

$ErrorActionPreference = "Continue"
$repoRoot = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $repoRoot "screenshots"
$package = "com.example.rolling_alarm"

New-Item -ItemType Directory -Force -Path $dest | Out-Null

$names = @(
    "01_home_screen.png",
    "02_routine_edit_screen.png",
    "03_active_countdown.png",
    "04_alarm_ring_screen.png",
    "05_logs_screen.png"
)

# Prefer app scoped external files (always writable by the app on API 29+).
$remoteRoots = @(
    "/sdcard/Android/data/$package/files/screenshots",
    "/storage/emulated/0/Android/data/$package/files/screenshots",
    "/data/local/tmp/rolling_alarm_screenshots",
    "/sdcard/Download/screenshots",
    "/sdcard/Pictures/screenshots"
)

function Test-ValidPng([string]$path) {
    if (-not (Test-Path $path)) { return $false }
    $item = Get-Item $path
    if ($item.Length -le 8) { return $false }
    $bytes = [System.IO.File]::ReadAllBytes($path)[0..7]
    return ($bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47)
}

$pulled = 0
foreach ($root in $remoteRoots) {
    foreach ($name in $names) {
        $remote = "$root/$name"
        $local = Join-Path $dest $name
        $null = adb pull $remote $local 2>&1
        if (($LASTEXITCODE -eq 0) -and (Test-ValidPng $local)) {
            Write-Host "Pulled $remote -> $local"
            $pulled++
        }
    }
}

# Directory pull fallback.
$null = adb pull "/sdcard/Android/data/$package/files/screenshots/." $dest 2>&1
$null = adb pull "/data/local/tmp/rolling_alarm_screenshots/." $dest 2>&1

# Debug builds: pull app documents screenshots via run-as when needed.
$missing = @($names | Where-Object { -not (Test-ValidPng (Join-Path $dest $_)) })
if ($missing.Count -gt 0) {
    foreach ($name in $missing) {
        $local = Join-Path $dest $name
        $remoteDocs = "app_flutter/screenshots/$name"
        adb exec-out run-as $package cat $remoteDocs > $local 2>$null
        if (Test-ValidPng $local) {
            Write-Host "Pulled via run-as $remoteDocs -> $local"
            $pulled++
        }
    }
}

Write-Host "Screenshot pull complete. Files in $dest :"
Get-ChildItem $dest -Filter "*.png" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host " - $($_.Name) ($($_.Length) bytes)"
}

$pngCount = @(Get-ChildItem $dest -Filter "*.png" -ErrorAction SilentlyContinue).Count
if ($pngCount -eq 0) {
    Write-Warning "No PNG files pulled. Run the screenshot integration test on a device first."
    exit 1
}

$stillMissing = @($names | Where-Object { -not (Test-ValidPng (Join-Path $dest $_)) })
if ($stillMissing.Count -gt 0) {
    Write-Warning ("Missing expected PNGs: " + ($stillMissing -join ", "))
    exit 1
}

Write-Host "All expected screenshot PNGs are present in $dest"
exit 0
