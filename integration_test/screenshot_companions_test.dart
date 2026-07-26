/// Screenshot suite companions: interval handoffs and FSI ring surface.
///
/// Kept separate from `screenshot_flow_test.dart` so PNG export stays green
/// even when OEM lockscreen / full-screen intent paths flake on API 34 AVDs.
///
/// Lockscreen limitation: turning the display off mid instrumentation (adb
/// keyevent 26) often drops the Flutter test VM connection. On-device
/// `Process.run('adb', ...)` also cannot reach the host adb binary. This file
/// therefore verifies the ring surface and ringing state after a simulated
/// isolate callback (the same path FSI / showWhenLocked ultimately present),
/// without power-button lock. Host scripts still grant USE_FULL_SCREEN_INTENT.
///
/// Run:
/// ```
/// .\scripts\adb_grant_exact_alarm.ps1
/// flutter test integration_test/screenshot_companions_test.dart -d emulator-5554 --no-uninstall
/// ```
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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

Future<void> _grantExactAlarmForScreenshotEnv() async {
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

  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('ra_db_path', dbPath);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [RA_DatabaseProvider.overrideWithValue(database)],
      child: RollingAlarmApp(dbPath: dbPath),
    ),
  );
  final homeReady = await pumpUntilFound(
    tester,
    find.text('Rolling Alarm'),
    timeout: const Duration(seconds: 20),
  );
  expect(homeReady, isTrue);
  return (dbPath, database);
}

Future<void> _ensureAlarmRingVisible(
  WidgetTester tester, {
  required int routineId,
  required String routineName,
}) async {
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
    expect(homeFinder, findsOneWidget);
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
  expect(find.byType(AlarmRingPage), findsOneWidget);
}

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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Companion: snooze/dismiss interval math across restart handoff',
    (WidgetTester tester) async {
      final (dbPath, database) = await _boot(tester);
      await _grantExactAlarmForScreenshotEnv();
      await pumpFrames(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await pumpFrames(tester);
      await tester.enterText(
        find.byType(TextField).first,
        'Restart Interval Routine',
      );
      await tester.tap(find.text('Save'));
      await pumpUntilFound(
        tester,
        find.text('Restart Interval Routine'),
        timeout: const Duration(seconds: 15),
      );

      final routines = await database.watchAllRoutines().first;
      final routine = routines.firstWhere(
        (r) => r.Name == 'Restart Interval Routine',
      );

      await RA_AlarmService.simulateAlarmCallback(routine.Id);
      await _ensureAlarmRingVisible(
        tester,
        routineId: routine.Id,
        routineName: routine.Name,
      );

      final firstRing = await database.getRoutineState(routine.Id);
      final initialRing = firstRing!.InitialRingTime!;

      await slideToSnooze(tester);
      await _waitForRingDismissed(tester, database, routine.Id);

      final afterSnooze = await database.getRoutineState(routine.Id);
      expect(afterSnooze!.CurrentSnoozeCount, 1);
      expect(afterSnooze.InitialRingTime, equals(initialRing));
      expect(afterSnooze.IsRinging, isFalse);
      expect(afterSnooze.NextTriggerTime, isNotNull);

      // Isolate handoff: second connection must see the same WAL-backed state.
      final isolateDb = RA_Database.openForIsolate(dbPath);
      try {
        final isolateView = await isolateDb.getRoutineState(routine.Id);
        expect(isolateView!.CurrentSnoozeCount, 1);
        expect(
          isolateView.NextTriggerTime,
          equals(afterSnooze.NextTriggerTime),
        );
        expect(isolateView.InitialRingTime, equals(initialRing));
      } finally {
        await isolateDb.close();
      }

      // Simulated cold start with the same DB file.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [RA_DatabaseProvider.overrideWithValue(database)],
          child: RollingAlarmApp(dbPath: dbPath),
        ),
      );
      await pumpUntilFound(
        tester,
        find.text('Restart Interval Routine'),
        timeout: const Duration(seconds: 15),
      );
      expect(find.text('Restart Interval Routine'), findsOneWidget);

      final afterRestart = await database.getRoutineState(routine.Id);
      expect(afterRestart!.CurrentSnoozeCount, 1);
      expect(afterRestart.NextTriggerTime, equals(afterSnooze.NextTriggerTime));

      await RA_AlarmService.simulateAlarmCallback(routine.Id);
      await _ensureAlarmRingVisible(
        tester,
        routineId: routine.Id,
        routineName: routine.Name,
      );
      await slideToDismiss(tester);
      await _waitForRingDismissed(tester, database, routine.Id);

      final dismissed = await database.getRoutineState(routine.Id);
      expect(dismissed!.IsRinging, isFalse);
      expect(dismissed.CurrentSnoozeCount, 0);
      expect(dismissed.NextTriggerTime, isNotNull);
    },
  );

  testWidgets(
    'Companion: FSI / showWhenLocked ring surface after isolate callback',
    (WidgetTester tester) async {
      final (_, database) = await _boot(tester);
      await _grantExactAlarmForScreenshotEnv();
      await pumpFrames(tester);

      // Host script grants USE_FULL_SCREEN_INTENT; Manifest has showWhenLocked.
      // Do not power-button lock here: screen-off drops the integration_test VM.
      await tester.tap(find.byType(FloatingActionButton));
      await pumpFrames(tester);
      await tester.enterText(
        find.byType(TextField).first,
        'FSI Lockscreen Routine',
      );
      await tester.tap(find.text('Save'));
      await pumpUntilFound(
        tester,
        find.text('FSI Lockscreen Routine'),
        timeout: const Duration(seconds: 15),
      );

      final routines = await database.watchAllRoutines().first;
      final routine = routines.firstWhere(
        (r) => r.Name == 'FSI Lockscreen Routine',
      );

      await RA_AlarmService.simulateAlarmCallback(routine.Id);
      await pumpFrames(tester, frames: 20);

      await _ensureAlarmRingVisible(
        tester,
        routineId: routine.Id,
        routineName: routine.Name,
      );
      expect(find.text('Slide to snooze'), findsOneWidget);
      expect(find.text('Slide to dismiss'), findsOneWidget);

      final ringing = await database.getRoutineState(routine.Id);
      expect(ringing!.IsRinging, isTrue);
      expect(ringing.InitialRingTime, isNotNull);
    },
  );
}
