Rolling Alarm store / QA screenshots
====================================

Expected PNG files (produced by integration_test/screenshot_flow_test.dart):
  01_home_screen.png
  02_routine_edit_screen.png
  03_active_countdown.png
  04_alarm_ring_screen.png
  05_logs_screen.png

On Android the test prefers app-scoped writable dirs (no extra storage Manifest
permission), typically:
  /sdcard/Android/data/com.example.rolling_alarm/files/screenshots/
  <app documents>/screenshots/   (pulled via run-as)

Pull into this folder after a device run:
  .\scripts\pull_screenshots.ps1

Grant SCHEDULE_EXACT_ALARM (and related appops) before / after first install:
  .\scripts\adb_grant_exact_alarm.ps1

Run the screenshot suite (recommended one-shot):
  .\scripts\run_screenshot_flow.ps1

Or manually:
  flutter test integration_test/screenshot_flow_test.dart -d emulator-5554 --no-uninstall
  .\scripts\pull_screenshots.ps1

Screenshot companions (snooze/dismiss restart handoff + FSI ring surface):
  flutter test integration_test/screenshot_companions_test.dart -d emulator-5554 --no-uninstall

Run Patrol native lifecycle suite:
  dart pub global activate patrol_cli
  $env:Path += ";$env:LOCALAPPDATA\Pub\Cache\bin"
  patrol test -t integration_test/advanced_alarm_lifecycle_test.dart

Run both:
  .\scripts\run_integration_tests.ps1

Lockscreen / FSI note:
  True OEM full-screen intent over an undismissed keyguard is AVD/OEM dependent.
  Power-button lock (adb keyevent 26) during flutter integration_test often drops
  the test VM connection on API 34 AVDs, and on-device Dart cannot reach host adb.
  Companions assert AlarmRingPage + IsRinging after the isolate callback (the same
  surface FSI / showWhenLocked present). Host scripts grant USE_FULL_SCREEN_INTENT.
  Manifest MainActivity sets showWhenLocked and turnScreenOn.

  Patrol on API 34 AVDs: power-button lock and notification-shade native taps have
  crashed the instrumentation process mid-suite. The Patrol suite therefore asserts
  exact-alarm grant, in-app FSI ring, and snooze/dismiss/isolate interval math.
