/// Rolling Alarm E2E screenshot harness.
///
/// Bindings use [IntegrationTestWidgetsFlutterBinding.ensureInitialized].
/// PNG bytes from [IntegrationTestWidgetsFlutterBinding.takeScreenshot] are
/// written under app-scoped storage on device. Host scripts create repo
/// `screenshots/` and pull PNGs via `scripts/run_screenshot_flow.ps1`.
///
/// Lifecycle / lockscreen companions live in
/// `screenshot_companions_test.dart` so a flaky FSI path cannot fail PNG export.
///
/// Run (device or emulator required):
/// ```
/// .\scripts\run_screenshot_flow.ps1
/// ```
/// Or manually:
/// ```
/// .\scripts\adb_grant_exact_alarm.ps1
/// flutter test integration_test/screenshot_flow_test.dart -d emulator-5554 --no-uninstall
/// .\scripts\pull_screenshots.ps1
/// ```
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rolling_alarm/components/routine/routine_countdown.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/main.dart';
import 'package:rolling_alarm/pages/alarm_ring.dart';
import 'package:rolling_alarm/pages/home.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/notification.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/android_alarm_test_helpers.dart';
import 'helpers/e2e_pump_helpers.dart';

/// PNG signature: 89 50 4E 47 0D 0A 1A 0A
bool _looksLikePng(List<int> bytes) =>
    bytes.length >= 8 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4E &&
    bytes[3] == 0x47 &&
    bytes[4] == 0x0D &&
    bytes[5] == 0x0A &&
    bytes[6] == 0x1A &&
    bytes[7] == 0x0A;

/// Writes [bytes] under every reachable screenshots destination.
///
/// On Android instrumentation the process cwd is not the host repo. Prefer
/// app-scoped external/files and documents dirs (no Manifest storage permission),
/// then best-effort public Download/Pictures for older images / rooted AVDs.
Future<List<String>> captureAndSaveScreenshot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String screenshotName,
) async {
  try {
    await binding.convertFlutterSurfaceToImage();
  } catch (_) {
    // Desktop / already-converted surface: ignore.
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  final List<int> bytes = await binding.takeScreenshot(screenshotName);
  expect(
    bytes,
    isNotEmpty,
    reason: 'takeScreenshot($screenshotName) must return PNG bytes',
  );
  expect(
    _looksLikePng(bytes),
    isTrue,
    reason: 'takeScreenshot($screenshotName) must return a PNG signature',
  );

  final fileName = '$screenshotName.png';
  final written = <String>[];

  Future<void> tryWrite(Directory dir) async {
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File(p.join(dir.path, fileName));
      await file.writeAsBytes(bytes, flush: true);
      expect(await file.exists(), isTrue);
      expect(await file.length(), greaterThan(8));
      written.add(file.path);
    } catch (e) {
      debugPrint('screenshot write skipped for ${dir.path}: $e');
    }
  }

  // Host-relative path (works when the test host can see the repo cwd).
  await tryWrite(Directory('screenshots'));
  await tryWrite(Directory('../screenshots'));
  await tryWrite(Directory('../../screenshots'));

  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    // World-readable tmp path so host scripts can adb pull into repo screenshots/.
    await tryWrite(Directory('/data/local/tmp/rolling_alarm_screenshots'));

    try {
      final docs = await getApplicationDocumentsDirectory();
      await tryWrite(Directory(p.join(docs.path, 'screenshots')));
    } catch (e) {
      debugPrint('documents screenshots path skipped: $e');
    }
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        await tryWrite(Directory(p.join(ext.path, 'screenshots')));
      }
    } catch (e) {
      debugPrint('external screenshots path skipped: $e');
    }
    try {
      final tmp = await getTemporaryDirectory();
      await tryWrite(Directory(p.join(tmp.path, 'screenshots')));
    } catch (e) {
      debugPrint('temp screenshots path skipped: $e');
    }
    // Best effort only; API 29+ often denies without storage permission.
    await tryWrite(Directory('/sdcard/Download/screenshots'));
    await tryWrite(Directory('/sdcard/Pictures/screenshots'));
    await tryWrite(
      Directory('/sdcard/Android/data/$kRollingAlarmPackage/files/screenshots'),
    );
  }

  expect(
    written,
    isNotEmpty,
    reason:
        'At least one screenshots destination must accept $fileName '
        '(app files/docs dir and/or host screenshots/)',
  );
  debugPrint('Saved $fileName -> ${written.join(', ')}');
  return written;
}

Future<void> _grantExactAlarmForScreenshotEnv() async {
  // Do not call Permission.*.request() here: without Patrol native automation
  // those calls open system dialogs/settings and hang flutter test forever.
  // Host scripts (adb_grant_exact_alarm.ps1 / run_screenshot_flow.ps1) must
  // pre-grant POST_NOTIFICATIONS + SCHEDULE_EXACT_ALARM before this suite.
  await grantNotificationViaAdb();
  await grantExactAlarmViaAdb();
  await grantFullScreenIntentViaAdb();
}

Future<(String dbPath, RA_Database database)> _boot(WidgetTester tester) async {
  configureIntegrationTestDrift();
  installKnownUiErrorFilter();

  final dbPath = await RA_Database.resolveDatabasePath();
  final database = RA_Database();
  registerTestUiPort(database);
  await RA_AlarmService.init();
  await RA_NotificationService.init();

  // Alarm isolate callbacks read this key; keep it set even before first schedule.
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('ra_db_path', dbPath);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [RA_DatabaseProvider.overrideWithValue(database)],
      child: RollingAlarmApp(dbPath: dbPath),
    ),
  );
  // Wait for Home chrome specifically; bounded pumps alone can finish before
  // the first frame paints on a cold emulator after reinstall.
  final homeReady = await pumpUntilFound(
    tester,
    find.text('Rolling Alarm'),
    timeout: const Duration(seconds: 20),
  );
  expect(
    homeReady,
    isTrue,
    reason: 'HomePage AppBar title must appear after pumpWidget',
  );
  return (dbPath, database);
}

Future<void> _ensureAlarmRingVisible(
  WidgetTester tester, {
  required int routineId,
  required String routineName,
}) async {
  // Give the HomePage ring listener a few seconds; then push as fallback.
  var shown = await pumpUntilFound(
    tester,
    find.byType(AlarmRingPage),
    timeout: const Duration(seconds: 6),
  );
  if (!shown) {
    await pumpUntilFound(
      tester,
      find.byType(HomePage),
      timeout: const Duration(seconds: 3),
    );
    final homeFinder = find.byType(HomePage);
    expect(
      homeFinder,
      findsOneWidget,
      reason: 'HomePage must be present to open AlarmRingPage fallback',
    );
    final homeContext = tester.element(homeFinder);
    unawaited(
      Navigator.push(
        homeContext,
        MaterialPageRoute(
          builder: (_) =>
              AlarmRingPage(routineId: routineId, routineName: routineName),
        ),
      ),
    );
    await pumpFrames(tester, frames: 20);
    shown = find.byType(AlarmRingPage).evaluate().isNotEmpty;
  }
  expect(
    shown || find.byType(AlarmRingPage).evaluate().isNotEmpty,
    isTrue,
    reason: 'AlarmRingPage must appear via ring listener or Navigator fallback',
  );
  expect(find.byType(AlarmRingPage), findsOneWidget);
}

/// After Snooze/Dismiss the routine name is still on AlarmRingPage, so waiting
/// for that text races. Wait until the ring route is gone, then assert DB.
Future<void> _waitForRingDismissed(
  WidgetTester tester,
  RA_Database database,
  int routineId,
) async {
  final gone = await pumpUntilGone(
    tester,
    find.byType(AlarmRingPage),
    timeout: const Duration(seconds: 20),
  );
  expect(gone, isTrue, reason: 'AlarmRingPage must pop after Snooze/Dismiss');

  final settled = await pumpUntilCondition(tester, () async {
    final state = await database.getRoutineState(routineId);
    return state != null && !state.IsRinging;
  }, timeout: const Duration(seconds: 10));
  expect(settled, isTrue, reason: 'Routine state must clear IsRinging');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Rolling Alarm E2E screenshot flow: capture primary screen states', (
    WidgetTester tester,
  ) async {
    final (_, database) = await _boot(tester);

    await _grantExactAlarmForScreenshotEnv();
    await pumpFrames(tester);

    // permission_handler status is authoritative on device. appops via adb from
    // the app process is usually unavailable, so host scripts must grant after
    // install (see run_screenshot_flow.ps1). Soft check, then prove scheduling.
    final exactStatus = await Permission.scheduleExactAlarm.status;
    if (!exactStatus.isGranted) {
      debugPrint(
        'SCHEDULE_EXACT_ALARM status=$exactStatus. '
        'Prefer scripts/run_screenshot_flow.ps1 (install then grant).',
      );
    }

    expect(find.text('Rolling Alarm'), findsOneWidget);

    // 01: home / routine overview
    await captureAndSaveScreenshot(binding, tester, '01_home_screen');

    // 02: routine create / edit
    await tester.tap(find.byType(FloatingActionButton));
    await pumpFrames(tester);
    expect(find.text('New Routine'), findsOneWidget);
    await captureAndSaveScreenshot(binding, tester, '02_routine_edit_screen');

    await tester.enterText(find.byType(TextField).first, 'Screenshot Routine');
    await tester.tap(find.text('Save'));
    await pumpUntilFound(
      tester,
      find.text('Screenshot Routine'),
      timeout: const Duration(seconds: 15),
    );
    expect(find.text('Screenshot Routine'), findsOneWidget);
    // Wait for the fade-pop of New Routine so 03 is not a blended frame.
    final editGone = await pumpUntilGone(
      tester,
      find.text('New Routine'),
      timeout: const Duration(seconds: 10),
    );
    expect(
      editGone,
      isTrue,
      reason: 'New Routine route must pop before countdown shot',
    );
    await pumpFrames(tester, frames: 10);

    // 03: active countdown on home after schedule
    await pumpUntilFound(tester, find.byType(RA_Countdown));
    expect(find.byType(RA_Countdown), findsWidgets);
    expect(find.text('New Routine'), findsNothing);
    expect(find.text('Interval'), findsNothing);
    await captureAndSaveScreenshot(binding, tester, '03_active_countdown');

    final routines = await database.watchAllRoutines().first;
    final routine = routines.firstWhere((r) => r.Name == 'Screenshot Routine');
    final stateBeforeRing = await database.getRoutineState(routine.Id);
    expect(stateBeforeRing?.NextTriggerTime, isNotNull);

    // Prove exact-alarm scheduling succeeded after host adb grant.
    expect(
      stateBeforeRing!.NextTriggerTime!.isAfter(
        DateTime.now().subtract(const Duration(minutes: 1)),
      ),
      isTrue,
      reason: 'NextTriggerTime must be set after SCHEDULE_EXACT_ALARM grant',
    );

    // 04: alarm ring (prefer real callback + HomePage navigator; push fallback)
    await RA_AlarmService.simulateAlarmCallback(routine.Id);
    await _ensureAlarmRingVisible(
      tester,
      routineId: routine.Id,
      routineName: routine.Name,
    );

    expect(find.text('Slide to dismiss'), findsOneWidget);
    expect(find.text('Slide to snooze'), findsOneWidget);
    await captureAndSaveScreenshot(binding, tester, '04_alarm_ring_screen');

    final ringing = await database.getRoutineState(routine.Id);
    expect(ringing?.IsRinging, isTrue);

    await slideToDismiss(tester);
    // TTS briefing + pop can take a few seconds on emulators.
    await _waitForRingDismissed(tester, database, routine.Id);
    expect(find.text('Rolling Alarm'), findsOneWidget);

    final afterDismiss = await database.getRoutineState(routine.Id);
    expect(afterDismiss?.IsRinging, isFalse);
    expect(afterDismiss?.NextTriggerTime, isNotNull);

    // 05: logs / history
    await tester.tap(find.byIcon(Icons.history));
    await pumpUntilFound(
      tester,
      find.text('Alarm Logs'),
      timeout: const Duration(seconds: 10),
    );
    expect(find.text('Alarm Logs'), findsOneWidget);
    await captureAndSaveScreenshot(binding, tester, '05_logs_screen');
  });
}
