# Grants SCHEDULE_EXACT_ALARM via adb appops for automated / CI environments.
# Usage: .\scripts\adb_grant_exact_alarm.ps1 [-PackageName com.example.rolling_alarm]

param(
    [string]$PackageName = "com.example.rolling_alarm"
)

$ErrorActionPreference = "Continue"

$devices = adb devices | Select-String -Pattern "device$"
if (-not $devices) {
    Write-Error "No adb device/emulator attached. Start an AVD or plug in a phone."
    exit 1
}

Write-Host "Granting SCHEDULE_EXACT_ALARM for $PackageName ..."
adb shell cmd appops set $PackageName SCHEDULE_EXACT_ALARM allow
if ($LASTEXITCODE -ne 0) {
    Write-Warning "appops set failed with exit $LASTEXITCODE (package may not be installed yet; re-run after first install)."
}

Write-Host "Current appops:"
adb shell cmd appops get $PackageName SCHEDULE_EXACT_ALARM

# Companion grants used by the alarm ring / screenshot path.
# POST_NOTIFICATIONS must be granted before flutter test, otherwise
# Permission.notification.request() (or first notification use) shows a dialog
# that blocks IntegrationTestWidgetsFlutterBinding suites without Patrol.
Write-Host "Granting POST_NOTIFICATIONS for $PackageName ..."
adb shell pm grant $PackageName android.permission.POST_NOTIFICATIONS 2>$null
adb shell cmd appops set $PackageName USE_FULL_SCREEN_INTENT allow 2>$null

Write-Host "Done."
