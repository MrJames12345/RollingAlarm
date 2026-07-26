@echo off
setlocal

set AVD_NAME=Modern_Phone
set FLUTTER_ARGS=
set DEVICE_ID=

if "%~1"=="" goto check_status
if /i "%~1"=="samsung" (
    set AVD_NAME=Samsung_Galaxy_S24
    shift
) else if /i "%~1"=="Modern_Phone" (
    set AVD_NAME=Modern_Phone
    shift
) else if /i "%~1"=="Old_Small_Phone" (
    set AVD_NAME=Old_Small_Phone
    shift
) else if /i "%~1"=="Tablet_Device" (
    set AVD_NAME=Tablet_Device
    shift
) else if /i "%~1"=="MyResizable" (
    set AVD_NAME=MyResizable
    shift
) else (
    set "ARG1=%~1"
    setlocal enabledelayedexpansion
    if not "!ARG1:~0,1!"=="-" if not "!ARG1:~0,1!"=="/" (
        endlocal
        set AVD_NAME=%~1
        shift
        goto collect_args
    )
    endlocal
)

:collect_args
if "%~1"=="" goto check_status
set FLUTTER_ARGS=%FLUTTER_ARGS% %1
shift
goto collect_args

:check_status
echo [1/3] Checking emulator status for %AVD_NAME%...
for /f "tokens=1" %%i in ('adb devices ^| findstr "emulator-"') do (
    adb -s %%i emu avd name 2>nul | findstr /i "%AVD_NAME%" >nul
    if not errorlevel 1 (
        set DEVICE_ID=%%i
    )
)

if not "%DEVICE_ID%"=="" (
    echo Android emulator %AVD_NAME% is already running on %DEVICE_ID%.
    goto wait_ready
)

echo Starting Android emulator: %AVD_NAME%
call flutter emulators --launch %AVD_NAME%

:wait_id
timeout /t 1 /nobreak >nul
for /f "tokens=1" %%i in ('adb devices ^| findstr "emulator-"') do (
    adb -s %%i emu avd name 2>nul | findstr /i "%AVD_NAME%" >nul
    if not errorlevel 1 (
        set DEVICE_ID=%%i
    )
)
if "%DEVICE_ID%"=="" goto wait_id

:wait_ready
echo [2/3] Waiting for emulator device (%DEVICE_ID%) to be ready...
adb -s %DEVICE_ID% wait-for-device

echo [3/3] Running Flutter application on %DEVICE_ID%...
call flutter run -d %DEVICE_ID%%FLUTTER_ARGS%

endlocal
