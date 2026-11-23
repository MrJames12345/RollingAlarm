@echo off
setlocal

cd /d "%~dp0"

set "RC_KEY=%~1"
if "%RC_KEY%"=="" set "RC_KEY=%REVENUECAT_ANDROID_API_KEY%"

if "%RC_KEY%"=="" (
    echo [ERROR] Missing production RevenueCat Android SDK key.
    echo.
    echo Usage:
    echo   buildRelease.bat goog_YOUR_PRODUCTION_ANDROID_KEY
    echo   or set REVENUECAT_ANDROID_API_KEY=goog_YOUR_PRODUCTION_ANDROID_KEY and run buildRelease.bat
    exit /b 1
)

powershell -NoProfile -Command ^
  "$k = $env:RC_KEY.Trim(); " ^
  "if ([string]::IsNullOrWhiteSpace($k)) { Write-Host '[ERROR] RevenueCat Android SDK key is empty.' -ForegroundColor Red; exit 1 }; " ^
  "if ($k -match '^(?i)test_') { Write-Host '[ERROR] Refusing to build a production release with a test RevenueCat key (test_...). Supply the production Android SDK key (goog_...).' -ForegroundColor Red; exit 1 }; " ^
  "if ($k -match '(?i)(placeholder|replace|your_|example|changeme|dummy|todo|xxx|\.\.\.|<|>|\s)') { Write-Host '[ERROR] RevenueCat Android SDK key contains placeholder text or whitespace. Supply the real production Android SDK key (goog_...).' -ForegroundColor Red; exit 1 }; " ^
  "if ($k -notmatch '^goog_[A-Za-z0-9_-]{8,}$') { Write-Host '[ERROR] Invalid production RevenueCat Android SDK key format. Expected a production Android key starting with goog_...' -ForegroundColor Red; exit 1 }"
if errorlevel 1 exit /b 1

for /f "usebackq delims=" %%K in (`powershell -NoProfile -Command "$env:RC_KEY.Trim()"`) do set "RC_KEY=%%K"

if not exist "android\key.properties" (
    echo [ERROR] Missing android\key.properties signing configuration.
    exit /b 1
)

for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "$m = Select-String -Path 'pubspec.yaml' -Pattern '^\s*version:\s*(\S+)' | Select-Object -First 1; if ($m) { $m.Matches[0].Groups[1].Value } else { '1.1.0+5' }"`) do set "APP_VERSION=%%V"

echo ============================================================
echo Building Rolling Alarm v%APP_VERSION% Production Release AAB
echo ============================================================

echo.
echo [1/4] Running flutter analyze...
call flutter analyze
if errorlevel 1 (
    echo [ERROR] flutter analyze failed. Aborting release build.
    exit /b 1
)

echo.
echo [2/4] Running flutter test...
call flutter test
if errorlevel 1 (
    echo [ERROR] flutter test failed. Aborting release build.
    exit /b 1
)

echo.
echo [3/4] Building signed release App Bundle (AAB)...
call flutter build appbundle --release --dart-define=REVENUECAT_ANDROID_API_KEY=%RC_KEY%
if errorlevel 1 (
    echo [ERROR] flutter build appbundle failed. Aborting release build.
    exit /b 1
)

set "SOURCE_AAB=build\app\outputs\bundle\release\app-release.aab"
if not exist "%SOURCE_AAB%" (
    echo [ERROR] Expected release bundle not found at %SOURCE_AAB%.
    exit /b 1
)

echo.
echo [4/4] Copying release bundle to Windows Desktop...
for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "[Environment]::GetFolderPath('Desktop')"`) do set "DESKTOP_DIR=%%D"

if "%DESKTOP_DIR%"=="" (
    echo [ERROR] Could not resolve Windows Desktop path.
    exit /b 1
)

set "DEST_AAB=%DESKTOP_DIR%\rolling_alarm_%APP_VERSION%.aab"
copy /y "%SOURCE_AAB%" "%DEST_AAB%" >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy %SOURCE_AAB% to %DEST_AAB%.
    exit /b 1
)

echo.
echo ============================================================
echo Release App Bundle Ready!
echo ============================================================
powershell -NoProfile -Command ^
  "$f = Get-Item -LiteralPath $env:DEST_AAB; " ^
  "$mb = [Math]::Round($f.Length / 1MB, 2); " ^
  "Write-Host ('Output Path: ' + $f.FullName); " ^
  "Write-Host ('File Size:   ' + $f.Length.ToString('N0') + ' bytes (' + $mb + ' MB)')"

endlocal
exit /b 0
