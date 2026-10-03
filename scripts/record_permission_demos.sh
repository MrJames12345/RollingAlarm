#!/usr/bin/env bash
#
# Records the three Google Play Console permission demonstration videos for
# Rolling Alarm on the connected emulator or device, with no manual steps:
#
#   exact_alarm_demo.mp4         SCHEDULE_EXACT_ALARM / USE_EXACT_ALARM
#                                Alarm armed for an exact time, screen locked,
#                                the device wakes and rings on time.
#   fullscreen_intent_demo.mp4   USE_FULL_SCREEN_INTENT
#                                Screen locked, the ring page opens full screen
#                                over the lock screen.
#   foreground_service_demo.mp4  FOREGROUND_SERVICE_SPECIAL_USE
#                                App sent to the home screen, the alarm rings
#                                from the foreground service, and the ongoing
#                                service notification is shown in the shade.
#
# The script builds a separate APK from lib/main_permission_demo.dart, which
# starts like the normal app but first seeds a routine due a few seconds after
# launch. The alarm is armed and fired by the app's real scheduling code, so
# every video shows genuine system behaviour. Videos are saved to the project
# root. When finished, app data is cleared and the normal debug build is
# reinstalled, so any routines previously on the device are lost.
#
# Usage (Git Bash, WSL, macOS or Linux):
#   ./scripts/record_permission_demos.sh
#
# Environment overrides:
#   ANDROID_SERIAL  Target a specific device when more than one is attached.
#   DEMOS           Space separated subset of: exact_alarm fullscreen_intent
#                   foreground_service
#   SKIP_BUILD      Set to 1 to reuse APKs from a previous run.
#   LEAD_SECONDS    Seconds from app launch until the alarm fires, default 20.
#   RING_SECONDS    Seconds of ringing kept in each video, default 8.

set -euo pipefail

# Git Bash on Windows rewrites arguments like /sdcard/... into host paths
# before they reach adb, which breaks device side file paths.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

cd "$(dirname "$0")/.."

APP_PACKAGE="com.casellaweb.rolling_alarm"
APP_ACTIVITY=".MainActivity"
RING_SERVICE="AlarmRingingService"
DEMOS="${DEMOS:-exact_alarm fullscreen_intent foreground_service}"
SKIP_BUILD="${SKIP_BUILD:-0}"
LEAD_SECONDS="${LEAD_SECONDS:-20}"
RING_SECONDS="${RING_SECONDS:-8}"
BUILD_DIR="build/permission_demos"
DEMO_APK="${BUILD_DIR}/demo.apk"
APP_APK="${BUILD_DIR}/app.apk"
FLUTTER_APK="build/app/outputs/flutter-apk/app-debug.apk"

case_check() {
  case "$1" in
    exact_alarm|fullscreen_intent|foreground_service) ;;
    *) echo "Error: unknown demo '$1'." >&2; exit 1 ;;
  esac
}
for demo in $DEMOS; do case_check "$demo"; done

if ! command -v adb >/dev/null 2>&1; then
  echo "Error: adb not found on PATH." >&2
  exit 1
fi
if ! adb get-state >/dev/null 2>&1; then
  echo "Error: no running emulator or device detected by adb." >&2
  exit 1
fi

# --------------------------------------------------------------------------- #
# Build
# --------------------------------------------------------------------------- #

if [[ "$SKIP_BUILD" == "1" && -f "$DEMO_APK" && -f "$APP_APK" ]]; then
  echo "Reusing APKs in ${BUILD_DIR}"
else
  mkdir -p "$BUILD_DIR"
  echo "Building normal debug APK (reinstalled when finished)..."
  flutter build apk --debug
  cp "$FLUTTER_APK" "$APP_APK"
  echo "Building demo APK from lib/main_permission_demo.dart..."
  flutter build apk --debug -t lib/main_permission_demo.dart
  cp "$FLUTTER_APK" "$DEMO_APK"
fi

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #

adb_value() {
  adb shell "$@" 2>/dev/null | tr -d '\r'
}

# Output is captured before grepping: with pipefail, grep -q exiting early
# would make the still writing adb side of a pipe report failure.
screen_is_on() {
  local power
  power="$(adb_value dumpsys power)"
  [[ "$power" == *"mWakefulness=Awake"* ]]
}

wake_and_unlock() {
  adb shell input keyevent KEYCODE_WAKEUP
  sleep 1
  adb shell wm dismiss-keyguard >/dev/null 2>&1 || true
  sleep 1
}

ring_service_running() {
  local services
  services="$(adb_value dumpsys activity services "$APP_PACKAGE")"
  [[ "$services" == *"$RING_SERVICE"* ]]
}

stop_recording() {
  adb shell pkill -INT screenrecord >/dev/null 2>&1 || true
  if [[ -n "${RECORD_PID:-}" ]]; then
    wait "$RECORD_PID" 2>/dev/null || true
    RECORD_PID=""
  fi
  # screenrecord needs a moment to finalise the MP4 after SIGINT.
  sleep 2
}

restore_device() {
  set +e
  echo "Restoring device..."
  stop_recording
  adb shell cmd statusbar collapse >/dev/null 2>&1
  adb shell am force-stop "$APP_PACKAGE" >/dev/null 2>&1
  adb shell pm clear "$APP_PACKAGE" >/dev/null 2>&1
  if [[ -f "$APP_APK" ]]; then
    echo "Reinstalling normal debug build..."
    adb install -r -g "$APP_APK" >/dev/null 2>&1 || echo "Warning: could not reinstall ${APP_APK}." >&2
  fi
  adb shell rm -f /sdcard/*_demo.mp4 >/dev/null 2>&1
  wake_and_unlock >/dev/null 2>&1
}
trap restore_device EXIT

validate_video() {
  local file="$1" size
  size=$(wc -c < "$file" | tr -d ' ')
  if (( size < 100 * 1024 )); then
    echo "Error: ${file} is only ${size} bytes." >&2
    return 1
  fi
  if [[ "$(od -An -c -j4 -N4 "$file" | tr -d ' \n')" != "ftyp" ]]; then
    echo "Error: ${file} is not an MP4 file." >&2
    return 1
  fi
  echo "  Saved ${file} (${size} bytes)"
}

# Waits for the alarm to ring: the ringing foreground service is running and
# the screen is on.
wait_for_ring() {
  local deadline=$(( SECONDS + LEAD_SECONDS + 45 ))
  while (( SECONDS < deadline )); do
    if ring_service_running && screen_is_on; then
      return 0
    fi
    sleep 0.5
  done
  echo "Error: the alarm did not ring within the expected time." >&2
  adb_value dumpsys activity services "$APP_PACKAGE" | grep -E "ServiceRecord|isForeground" >&2 || true
  adb_value dumpsys power | grep -E "mWakefulness=" >&2 || true
  return 1
}

wait_for_ready() {
  local deadline=$(( SECONDS + 60 ))
  while (( SECONDS < deadline )); do
    if [[ "$(adb logcat -d -s flutter:I 2>/dev/null)" == *"RA_DEMO_READY"* ]]; then
      return 0
    fi
    sleep 0.5
  done
  echo "Error: the demo app did not report ready within 60s." >&2
  return 1
}

record_demo() {
  local demo="$1"
  local device_file="/sdcard/${demo}_demo.mp4"
  local output_file="./${demo}_demo.mp4"

  echo "== ${demo} =="
  adb shell am force-stop "$APP_PACKAGE"
  adb shell cmd statusbar collapse >/dev/null 2>&1 || true
  wake_and_unlock
  adb shell input keyevent KEYCODE_HOME
  sleep 1
  adb logcat -c
  rm -f "$output_file"

  adb shell screenrecord --time-limit 170 "$device_file" &
  RECORD_PID=$!
  sleep 2

  echo "  Launching the app with an alarm due in ${LEAD_SECONDS}s"
  adb shell am start -S -n "${APP_PACKAGE}/${APP_ACTIVITY}" --es route "'/demo?in=${LEAD_SECONDS}'" >/dev/null
  wait_for_ready
  # Let the viewer see the routine counting down before leaving the app.
  sleep 4

  case "$demo" in
    exact_alarm|fullscreen_intent)
      echo "  Locking the screen"
      adb shell input keyevent KEYCODE_SLEEP
      ;;
    foreground_service)
      echo "  Sending the app to the home screen"
      adb shell input keyevent KEYCODE_HOME
      ;;
  esac

  echo "  Waiting for the alarm to ring"
  wait_for_ring
  echo "  Ringing"
  sleep "$RING_SECONDS"

  if [[ "$demo" == "foreground_service" ]]; then
    echo "  Showing the foreground service notification"
    adb shell cmd statusbar expand-notifications
    sleep 5
    adb shell cmd statusbar collapse
    sleep 2
  fi

  stop_recording
  adb pull "$device_file" "$output_file" >/dev/null
  adb shell rm -f "$device_file"
  validate_video "$output_file"

  # Stops the ringing service before the next demo.
  adb shell am force-stop "$APP_PACKAGE"
}

# --------------------------------------------------------------------------- #
# Prepare device
# --------------------------------------------------------------------------- #

echo "Installing demo APK..."
adb install -r -g "$DEMO_APK" >/dev/null

# The same access the app requests on first launch, granted up front so no
# permission screens appear in the videos.
echo "Granting permissions..."
adb shell pm grant "$APP_PACKAGE" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
adb shell appops set "$APP_PACKAGE" SCHEDULE_EXACT_ALARM allow >/dev/null 2>&1 || true
adb shell appops set "$APP_PACKAGE" USE_FULL_SCREEN_INTENT allow >/dev/null 2>&1 || true
adb shell appops set "$APP_PACKAGE" SYSTEM_ALERT_WINDOW allow >/dev/null 2>&1 || true
adb shell dumpsys deviceidle whitelist "+${APP_PACKAGE}" >/dev/null 2>&1 || true

# --------------------------------------------------------------------------- #
# Record
# --------------------------------------------------------------------------- #

RECORD_PID=""
for demo in $DEMOS; do
  record_demo "$demo"
done
echo "All videos saved to the project root."
