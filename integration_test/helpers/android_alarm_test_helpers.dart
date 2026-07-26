import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:patrol/patrol.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/services/alarm.dart';

/// Android package under test (must match pubspec patrol.android.package_name).
const String kRollingAlarmPackage = 'com.example.rolling_alarm';

/// Quiets Drift's multi-connection warning for UI + openForIsolate E2E paths.
///
/// Production uses separate isolates; tests intentionally open a second
/// connection on the same file to assert WAL handoffs.
void configureIntegrationTestDrift() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
}

/// Mirrors [main] UI port wiring so isolate alarm callbacks refresh Drift watches.
void registerTestUiPort(RA_Database database) {
  RA_AlarmService.registerUiPort(
    (_) => database.notifyUpdates({
      TableUpdate.onTable(database.routines),
      TableUpdate.onTable(database.routineStates),
      TableUpdate.onTable(database.logEntries),
    }),
  );
}

/// Grants standard runtime permissions (e.g. POST_NOTIFICATIONS) via Patrol.
Future<void> grantRuntimePermissions(PatrolIntegrationTester $) async {
  // ignore: deprecated_member_use
  if (await $.native.isPermissionDialogVisible()) {
    // ignore: deprecated_member_use
    await $.native.grantPermissionWhenInUse();
  }
}

/// Best effort attempt to complete the Alarms and reminders settings UI flow.
///
/// SCHEDULE_EXACT_ALARM is an app ops special access toggle, not a runtime
/// permission dialog. permission_handler opens ACTION_REQUEST_SCHEDULE_EXACT_ALARM;
/// OEM skins and locales make the native toggle brittle, so callers should
/// always follow this with [grantExactAlarmViaAdb].
///
/// Every step is hard timed out: some OEM Settings screens never return from
/// [Permission.scheduleExactAlarm.request], which previously hung Patrol runs.
Future<void> attemptNativeExactAlarmSettingsFlow(
  PatrolIntegrationTester $,
) async {
  try {
    await Permission.scheduleExactAlarm
        .request()
        .timeout(const Duration(seconds: 6));
  } catch (_) {}

  try {
    // ignore: deprecated_member_use
    await $.native.tap(
      Selector(text: 'Allow setting alarms and reminders'),
      timeout: const Duration(seconds: 3),
    );
  } catch (_) {
    try {
      // ignore: deprecated_member_use
      await $.native.tap(
        Selector(textContains: 'Allow'),
        timeout: const Duration(seconds: 2),
      );
    } catch (_) {}
  }

  try {
    // ignore: deprecated_member_use
    await $.native.pressBack();
  } catch (_) {}

  try {
    // ignore: deprecated_member_use
    await $.native.openApp(appId: kRollingAlarmPackage);
  } catch (_) {}
}

/// Best-effort adb grant from a process that can see the host adb binary.
///
/// When Dart runs inside the Android app (flutter test / patrol on device),
/// `adb` is usually unavailable and these helpers no-op. Prefer host scripts
/// `scripts/adb_grant_exact_alarm.ps1` and `scripts/run_screenshot_flow.ps1`
/// which grant after APK install. Patrol suites additionally use native
/// Settings automation in [ensureScheduleExactAlarmAllowed].
Future<ProcessResult?> grantNotificationViaAdb({
  String packageName = kRollingAlarmPackage,
}) async {
  try {
    return await Process.run('adb', [
      'shell',
      'pm',
      'grant',
      packageName,
      'android.permission.POST_NOTIFICATIONS',
    ]).timeout(const Duration(seconds: 3));
  } catch (_) {
    return null;
  }
}

/// Best-effort SCHEDULE_EXACT_ALARM grant via adb appops (host-side preferred).
Future<ProcessResult?> grantExactAlarmViaAdb({
  String packageName = kRollingAlarmPackage,
}) async {
  try {
    return await Process.run('adb', [
      'shell',
      'cmd',
      'appops',
      'set',
      packageName,
      'SCHEDULE_EXACT_ALARM',
      'allow',
    ]).timeout(const Duration(seconds: 3));
  } catch (_) {
    return null;
  }
}

/// Reads the current SCHEDULE_EXACT_ALARM appops mode for [packageName].
Future<String?> readExactAlarmAppOps({
  String packageName = kRollingAlarmPackage,
}) async {
  try {
    final result = await Process.run('adb', [
      'shell',
      'cmd',
      'appops',
      'get',
      packageName,
      'SCHEDULE_EXACT_ALARM',
    ]).timeout(const Duration(seconds: 3));
    if (result.exitCode != 0) return null;
    return (result.stdout as String).trim();
  } catch (_) {
    return null;
  }
}

/// Full permission path for exact alarms and related special access.
///
/// Grants via adb first so CI / emulator runs never hang on OEM Settings, then
/// best effort attempts the native Alarms and reminders UI (plan requirement)
/// behind timeouts. Runtime notification dialogs are handled last.
Future<void> ensureScheduleExactAlarmAllowed(
  PatrolIntegrationTester $,
) async {
  await grantRuntimePermissions($);
  // Deterministic app-ops grants before any Settings deep link that can hang.
  await grantNotificationViaAdb();
  await grantExactAlarmViaAdb();
  await grantFullScreenIntentViaAdb();
  try {
    await attemptNativeExactAlarmSettingsFlow($)
        .timeout(const Duration(seconds: 20));
  } catch (_) {}

  try {
    await Permission.notification
        .request()
        .timeout(const Duration(seconds: 5));
  } catch (_) {}
}

/// Host-only helpers: power-button lock / wake via adb.
///
/// Do not call these from flutter integration_test bodies on device. Screen-off
/// (keyevent 26) frequently drops the instrumentation VM connection on API 34
/// AVDs, and on-device Dart usually cannot reach the host `adb` binary anyway.
/// Prefer host scripts for lockscreen experiments; in-app suites assert the
/// AlarmRingPage surface that FSI / showWhenLocked ultimately present.
Future<void> lockScreenViaAdb() async {
  try {
    await Process.run('adb', [
      'shell',
      'input',
      'keyevent',
      '26',
    ]).timeout(const Duration(seconds: 3));
  } catch (_) {}
}

/// Host-only: wake the device and dismiss the keyguard for UI assertions.
Future<void> wakeAndDismissKeyguardViaAdb() async {
  try {
    await Process.run('adb', [
      'shell',
      'input',
      'keyevent',
      '224',
    ]).timeout(const Duration(seconds: 3));
    await Process.run('adb', [
      'shell',
      'wm',
      'dismiss-keyguard',
    ]).timeout(const Duration(seconds: 3));
  } catch (_) {}
}

/// Best effort grant of USE_FULL_SCREEN_INTENT via adb appops (API 34+).
Future<ProcessResult?> grantFullScreenIntentViaAdb({
  String packageName = kRollingAlarmPackage,
}) async {
  try {
    return await Process.run('adb', [
      'shell',
      'cmd',
      'appops',
      'set',
      packageName,
      'USE_FULL_SCREEN_INTENT',
      'allow',
    ]).timeout(const Duration(seconds: 3));
  } catch (_) {
    return null;
  }
}
