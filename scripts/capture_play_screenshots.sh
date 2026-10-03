#!/usr/bin/env bash
#
# Captures Google Play Store screenshots of Rolling Alarm from the running
# emulator for phone, 7-inch tablet and 10-inch tablet listings, with a clean
# demo mode status bar and the device clock pinned to 07:00.
#
# No manual setup is needed in the app. The script builds a separate APK from
# lib/main_screenshots.dart, which wipes app data on every launch, seeds demo
# routines and log history, and opens the scene requested through the
# FlutterActivity "route" intent extra. When finished, app data is cleared and
# the normal debug build is reinstalled, so any routines previously on the
# emulator are lost.
#
# Scenes, in store listing order:
#   01_dashboard        Home with daily cap, paused, muted and countdown cards
#   02_alarm_ringing    Full screen ring page with snooze and dismiss sliders
#   03_routine_editor   Edit Routine scrolled to the interval settings
#   04_routine_summary  Routine summary tiles
#   05_alarm_logs       Alarm log history with mixed event types
#   06_settings         Settings
#
# Every scene is captured in the dark theme only, at least 1,080 px wide.
#
# Display profiles (every capture is exactly 9:16):
#   phone        1080x1920 at 420 dpi (411 dp wide phone)
#   tablet_7in   1080x1920 at 288 dpi (600 dp smallest width)
#   tablet_10in  1440x2560 at 288 dpi (800 dp smallest width)
#
# Play Console requirements (PNG or JPEG, up to 8 MB, 16:9 or 9:16):
#   phone, 7-inch: each side between 320 px and 3,840 px
#   10-inch:       each side between 1,080 px and 7,680 px
#
# The screenshot build hides the navigation bar (and the tablet taskbar) and
# keeps the status bar.
#
# Temporary emulator changes, all restored on exit (including on failure):
#   demo mode status bar, display size and density, the "Viewing full screen"
#   tip, and the system clock (needs `adb root`, which works on Google APIs
#   images; skipped with a warning on Google Play images).
#
# Usage (from any directory, in Git Bash, WSL, macOS or Linux):
#   ./scripts/capture_play_screenshots.sh [output_dir]
#
# Output:
#   <output_dir>/<profile>/<scene>.png, default output_dir screenshots/play_store
#
# Environment overrides:
#   ANDROID_SERIAL  Target a specific device when more than one is attached.
#   PROFILES        Space separated subset of: phone tablet_7in tablet_10in
#   SCENES          Space separated subset of the scene names above
#   SKIP_BUILD      Set to 1 to reuse APKs from a previous run.
#   SETTLE_WAIT     Extra seconds to wait after a scene reports ready, default 1
#   READY_TIMEOUT   Seconds to wait for a scene to report ready, default 60

set -euo pipefail

# Git Bash on Windows rewrites arguments like /sdcard/... into host paths
# before they reach adb, which breaks device side file paths.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

cd "$(dirname "$0")/.."

APP_PACKAGE="com.casellaweb.rolling_alarm"
APP_ACTIVITY=".MainActivity"
PROFILES="${PROFILES:-phone tablet_7in tablet_10in}"
SCENES="${SCENES:-01_dashboard 02_alarm_ringing 03_routine_editor 04_routine_summary 05_alarm_logs 06_settings}"
MIN_WIDTH=1080
SKIP_BUILD="${SKIP_BUILD:-0}"
SETTLE_WAIT="${SETTLE_WAIT:-1}"
READY_TIMEOUT="${READY_TIMEOUT:-60}"
OUTPUT_DIR="${1:-screenshots/play_store}"
BUILD_DIR="build/play_screenshots"
SCREENSHOT_APK="${BUILD_DIR}/screenshots.apk"
APP_APK="${BUILD_DIR}/app.apk"
FLUTTER_APK="build/app/outputs/flutter-apk/app-debug.apk"
DEVICE_TMP="/sdcard/play_screenshot_tmp.png"

# "<size> <density> <min side> <max side>" per display profile.
profile_spec() {
  case "$1" in
    phone)       echo "1080x1920 420 320 3840" ;;
    tablet_7in)  echo "1080x1920 288 320 3840" ;;
    tablet_10in) echo "1440x2560 288 1080 7680" ;;
    *) echo "Error: unknown profile '$1'." >&2; exit 1 ;;
  esac
}

# Route passed to lib/main_screenshots.dart for each scene.
scene_route() {
  case "$1" in
    01_dashboard)       echo "/dashboard" ;;
    02_alarm_ringing)   echo "/ringing" ;;
    03_routine_editor)  echo "/editor" ;;
    04_routine_summary) echo "/summary" ;;
    05_alarm_logs)      echo "/logs" ;;
    06_settings)        echo "/settings" ;;
    *) echo "Error: unknown scene '$1'." >&2; exit 1 ;;
  esac
}

for profile in $PROFILES; do profile_spec "$profile" >/dev/null; done
for scene in $SCENES; do scene_route "$scene" >/dev/null; done

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

if [[ "$SKIP_BUILD" == "1" && -f "$SCREENSHOT_APK" && -f "$APP_APK" ]]; then
  echo "Reusing APKs in ${BUILD_DIR}"
else
  if ! command -v flutter >/dev/null 2>&1; then
    echo "Error: flutter not found on PATH." >&2
    exit 1
  fi
  mkdir -p "$BUILD_DIR"
  echo "Building normal debug APK (reinstalled when finished)..."
  flutter build apk --debug
  cp "$FLUTTER_APK" "$APP_APK"
  echo "Building screenshot APK from lib/main_screenshots.dart..."
  flutter build apk --debug -t lib/main_screenshots.dart
  cp "$FLUTTER_APK" "$SCREENSHOT_APK"
fi

# --------------------------------------------------------------------------- #
# Emulator state helpers
# --------------------------------------------------------------------------- #

adb_value() {
  adb shell "$@" 2>/dev/null | tr -d '\r'
}

demo() {
  adb shell am broadcast -a com.android.systemui.demo -e command "$@" >/dev/null
}

apply_clean_status_bar() {
  demo enter
  demo notifications -e visible false
  demo battery -e level 100 -e plugged false -e powersave false
  # Full strength Wi-Fi and cellular with no data type badge, as on a phone
  # connected to Wi-Fi.
  demo network -e airplane hide -e nosim hide
  demo network -e wifi show -e level 4 -e fully true
  demo network -e mobile show -e level 4 -e datatype none -e fully true
  # The app keeps alarms scheduled, so the system alarm icon is shown.
  demo status -e alarm show -e volume hide -e bluetooth hide -e location hide \
    -e zen hide -e mute hide -e speakerphone hide -e cast hide -e hotspot hide \
    -e sync hide -e tty hide -e eri hide
  demo clock -e hhmm 0700
}

reset_display() {
  adb shell wm size reset >/dev/null 2>&1 || true
  adb shell wm density reset >/dev/null 2>&1 || true
}

ORIGINAL_AUTO_TIME="$(adb_value settings get global auto_time)"
ORIGINAL_IMMERSIVE_CONFIRMATIONS="$(adb_value settings get secure immersive_mode_confirmations)"
WAS_ROOT=0
[[ "$(adb_value id -u)" == "0" ]] && WAS_ROOT=1
CLOCK_CONTROL=0
CHANGED_CLOCK=0

restore_emulator() {
  set +e
  echo "Restoring emulator..."
  # Force-stop and clear before the clock moves forward, so alarms the demo
  # data armed at 07:00 cannot fire once real time is restored.
  adb shell am force-stop "$APP_PACKAGE" >/dev/null 2>&1
  adb shell pm clear "$APP_PACKAGE" >/dev/null 2>&1
  if [[ -f "$APP_APK" ]]; then
    echo "Reinstalling normal debug build..."
    adb install -r "$APP_APK" >/dev/null 2>&1 || echo "Warning: could not reinstall ${APP_APK}." >&2
  fi
  reset_display
  if [[ -z "$ORIGINAL_IMMERSIVE_CONFIRMATIONS" || "$ORIGINAL_IMMERSIVE_CONFIRMATIONS" == "null" ]]; then
    adb shell settings delete secure immersive_mode_confirmations >/dev/null 2>&1
  else
    adb shell settings put secure immersive_mode_confirmations "$ORIGINAL_IMMERSIVE_CONFIRMATIONS" >/dev/null 2>&1
  fi
  demo exit
  adb shell settings put global sysui_demo_allowed 0 >/dev/null 2>&1
  if (( CHANGED_CLOCK )); then
    adb shell "date @$(date +%s)" >/dev/null 2>&1
  fi
  if [[ -n "$ORIGINAL_AUTO_TIME" && "$ORIGINAL_AUTO_TIME" != "null" ]]; then
    adb shell settings put global auto_time "$ORIGINAL_AUTO_TIME" >/dev/null 2>&1
  fi
  adb shell rm -f "$DEVICE_TMP" >/dev/null 2>&1
  if (( CLOCK_CONTROL && ! WAS_ROOT )); then
    adb unroot >/dev/null 2>&1
    adb wait-for-device >/dev/null 2>&1
  fi
}

trap restore_emulator EXIT

# Pins the device clock to 07:00:00 today so in-app times match the status bar.
pin_clock() {
  (( CLOCK_CONTROL )) || return 0
  local day year
  day="$(adb_value date +%m%d)"
  year="$(adb_value date +%Y)"
  adb shell "date ${day}0700${year}.00" >/dev/null
  CHANGED_CLOCK=1
}

# Prints "<width> <height>" read from the PNG IHDR chunk.
png_dimensions() {
  od -An -tu1 -j16 -N8 "$1" | awk '{
    printf "%d %d\n", ($1*16777216)+($2*65536)+($3*256)+$4, ($5*16777216)+($6*65536)+($7*256)+$8
  }'
}

# Checks a capture against the Play Console rules for its profile.
validate_screenshot() {
  local file="$1" min_side="$2" max_side="$3"
  local width height size_bytes long short

  if [[ "$(od -An -tx1 -N8 "$file" | tr -d ' \n')" != "89504e470d0a1a0a" ]]; then
    echo "Error: ${file} is not a valid PNG." >&2
    return 1
  fi

  read -r width height < <(png_dimensions "$file")
  size_bytes=$(wc -c < "$file" | tr -d ' ')
  long=$(( width > height ? width : height ))
  short=$(( width > height ? height : width ))

  if (( size_bytes > 8 * 1024 * 1024 )); then
    echo "Error: ${file} is ${size_bytes} bytes, over the 8 MB limit." >&2
    return 1
  fi
  if (( short < min_side || long > max_side )); then
    echo "Error: ${file} is ${width}x${height}, sides must be between ${min_side} and ${max_side} px." >&2
    return 1
  fi
  if (( width < MIN_WIDTH )); then
    echo "Error: ${file} is ${width}x${height}, narrower than ${MIN_WIDTH} px." >&2
    return 1
  fi
  if (( long * 9 != short * 16 )); then
    echo "Error: ${file} is ${width}x${height}, which is not a 16:9 or 9:16 aspect ratio." >&2
    return 1
  fi

  echo "  Validated ${file} (${width}x${height}, ${size_bytes} bytes)"
}

wait_for_scene_ready() {
  local route="$1" deadline=$(( SECONDS + READY_TIMEOUT ))
  while (( SECONDS < deadline )); do
    if adb logcat -d -s flutter:I 2>/dev/null | grep -qF "RA_SCREENSHOT_READY ${route}"; then
      return 0
    fi
    sleep 0.5
  done
  echo "Error: scene ${route} did not report ready within ${READY_TIMEOUT}s." >&2
  return 1
}

capture_scene() {
  local scene="$1" profile_dir="$2" min_side="$3" max_side="$4"
  local route output_file
  route="$(scene_route "$scene")"
  output_file="${profile_dir}/${scene}.png"

  echo "  ${scene} (${route})"
  rm -f "$output_file"
  pin_clock || return 1
  adb logcat -c || return 1
  adb shell am start -S -n "${APP_PACKAGE}/${APP_ACTIVITY}" --es route "'${route}'" >/dev/null || return 1
  wait_for_scene_ready "$route" || return 1
  sleep "$SETTLE_WAIT"
  # System notifications posted after demo mode was entered (such as the
  # emulator's "Serial console enabled") show their icons again until the
  # demo commands are resent, so they go out immediately before every capture.
  apply_clean_status_bar || return 1
  sleep 0.5

  adb shell screencap -p "$DEVICE_TMP" || return 1
  adb pull "$DEVICE_TMP" "$output_file" >/dev/null || return 1
  validate_screenshot "$output_file" "$min_side" "$max_side"
}

# The emulator's adb connection occasionally drops for a moment, so each scene
# gets one retry after the device is reachable again.
capture_scene_with_retry() {
  if capture_scene "$@"; then
    return 0
  fi
  echo "  Retrying $1 after an adb error..." >&2
  sleep 3
  adb wait-for-device
  capture_scene "$@"
}

capture_profile() {
  local profile="$1"
  local size density min_side max_side profile_dir
  read -r size density min_side max_side < <(profile_spec "$profile")
  profile_dir="${OUTPUT_DIR}/${profile}"

  echo "== ${profile}: ${size} at ${density} dpi =="
  # Chrome's GPU process restarts on every density change, and on emulators
  # using host Vulkan that restart can freeze the whole emulator.
  adb shell am force-stop com.android.chrome >/dev/null 2>&1 || true
  adb shell wm size "$size"
  adb shell wm density "$density"
  # A display or density change rebuilds the status bar, and icons such as the
  # cellular signal are only redrawn when demo mode is entered from scratch.
  sleep 2
  demo exit
  sleep 1
  apply_clean_status_bar

  mkdir -p "$profile_dir"
  for scene in $SCENES; do
    capture_scene_with_retry "$scene" "$profile_dir" "$min_side" "$max_side"
  done
}

# --------------------------------------------------------------------------- #
# Prepare emulator
# --------------------------------------------------------------------------- #

# -g grants every runtime permission in the manifest at install time. The
# explicit grants below cover special access that -g does not, all before the
# app is first launched, so no permission dialogs or settings screens cover
# the UI. Failures are ignored for API levels where a permission or app-op
# does not exist.
echo "Installing screenshot APK..."
adb install -r -g "$SCREENSHOT_APK" >/dev/null
echo "Pre-granting permissions..."
adb shell pm grant "$APP_PACKAGE" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
adb shell appops set "$APP_PACKAGE" SCHEDULE_EXACT_ALARM allow >/dev/null 2>&1 || true
adb shell appops set "$APP_PACKAGE" SYSTEM_ALERT_WINDOW allow >/dev/null 2>&1 || true
adb shell appops set "$APP_PACKAGE" USE_FULL_SCREEN_INTENT allow >/dev/null 2>&1 || true
adb shell dumpsys deviceidle whitelist "+${APP_PACKAGE}" >/dev/null 2>&1 || true

echo "Enabling demo mode..."
adb shell settings put global sysui_demo_allowed 1

# Suppress the one time "Viewing full screen" tip that appears when the
# screenshot build hides the navigation bar.
adb shell settings put secure immersive_mode_confirmations confirmed

if (( WAS_ROOT )); then
  CLOCK_CONTROL=1
else
  adb root >/dev/null 2>&1 || true
  # adbd restarts asynchronously, so wait-for-device can return while the old
  # non root daemon is still answering. Poll until uid 0 shows up.
  for _ in $(seq 1 20); do
    adb wait-for-device >/dev/null 2>&1 || true
    if [[ "$(adb_value id -u 2>/dev/null)" == "0" ]]; then
      CLOCK_CONTROL=1
      break
    fi
    sleep 1
  done
fi
if (( CLOCK_CONTROL )); then
  echo "Pinning the device clock to 07:00 for each capture..."
  adb shell settings put global auto_time 0
else
  echo "Warning: adb root unavailable, in-app times will use the real clock." >&2
fi

# --------------------------------------------------------------------------- #
# Capture
# --------------------------------------------------------------------------- #

for profile in $PROFILES; do
  capture_profile "$profile"
done

echo "All screenshots saved under ${OUTPUT_DIR}"
