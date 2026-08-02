import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/alarm_action_type_code.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';
import 'package:rolling_alarm/enums/log_action_type_code.dart';
import 'package:rolling_alarm/main.dart';
import 'package:rolling_alarm/pages/alarm_ring.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/alarm_calculator.dart';
import 'package:rolling_alarm/services/notification.dart';

import 'helpers/android_alarm_test_helpers.dart';
import 'helpers/e2e_pump_helpers.dart';

/// Single patrolTest body on purpose: API 34 AVDs were crashing the
/// instrumentation process between Parametrized JUnit cases after the first
/// green Dart test.
///
/// Lockscreen power-button + notification-shade native flows also crash the
/// Patrol process on this AVD; those paths are covered by
/// `screenshot_flow_test.dart` companions (which passed on emulator-5554).
Future<(String dbPath, RA_Database database)> _bootApp(
  PatrolIntegrationTester $,
) async {
  configureIntegrationTestDrift();
  installKnownUiErrorFilter();

  final dbPath = await RA_Database.resolveDatabasePath();
  final database = RA_Database();
  registerTestUiPort(database);
  await RA_AlarmService.init();
  await RA_NotificationService.init();

  await $.pumpWidget(
    ProviderScope(
      overrides: [RA_DatabaseProvider.overrideWithValue(database)],
      child: RollingAlarmApp(dbPath: dbPath),
    ),
  );
  await pumpFrames($.tester);

  return (dbPath, database);
}

Future<void> _simulateAppRestart(
  PatrolIntegrationTester $, {
  required String dbPath,
  required RA_Database database,
}) async {
  await $.pumpWidget(
    ProviderScope(
      overrides: [RA_DatabaseProvider.overrideWithValue(database)],
      child: RollingAlarmApp(dbPath: dbPath),
    ),
  );
  await pumpFrames($.tester);
}

Future<void> _waitForRingGone(
  PatrolIntegrationTester $,
  RA_Database database,
  int routineId,
) async {
  final gone = await pumpUntilGone(
    $.tester,
    find.byType(AlarmRingPage),
    timeout: const Duration(seconds: 20),
  );
  expect(gone, isTrue, reason: 'AlarmRingPage must pop after action');
  final settled = await pumpUntilCondition(
    $.tester,
    () async {
      final state = await database.getRoutineState(routineId);
      return state != null && !state.IsRinging;
    },
  );
  expect(settled, isTrue);
}

void main() {
  patrolTest(
    'Advanced Android alarm lifecycle: exact alarm, FSI ring, snooze/dismiss, isolates',
    ($) async {
      final (dbPath, database) = await _bootApp($);

      // -------------------------------------------------------------------
      // 1) SCHEDULE_EXACT_ALARM: native attempt + adb appops fallback
      // -------------------------------------------------------------------
      await ensureScheduleExactAlarmAllowed($);
      await pumpFrames($.tester);

      expect($('Rolling Alarm'), findsOneWidget);

      final status = await Permission.scheduleExactAlarm.status;
      final appOps = await readExactAlarmAppOps();
      expect(
        status.isGranted ||
            (appOps != null && appOps.toLowerCase().contains('allow')),
        isTrue,
        reason:
            'SCHEDULE_EXACT_ALARM must be allowed via permission_handler '
            'or the adb appops fallback (got status=$status, appops=$appOps)',
      );

      await $(FloatingActionButton).tap();
      await pumpFrames($.tester);
      await $(TextField).first.enterText('Exact Alarm Permission Routine');
      await $('Save').tap();
      await pumpUntilFound(
        $.tester,
        find.text('Exact Alarm Permission Routine'),
        timeout: const Duration(seconds: 15),
      );

      final permissionRoutines = await database.watchAllRoutines().first;
      final permissionRoutine = permissionRoutines.firstWhere(
        (r) => r.Name == 'Exact Alarm Permission Routine',
      );
      final permissionState = await database.getRoutineState(
        permissionRoutine.Id,
      );
      expect(permissionState?.NextTriggerTime, isNotNull);
      expect(permissionState!.IsRinging, isFalse);

      // -------------------------------------------------------------------
      // 2) Full-screen intent path without power-button lock
      //
      // Limitation: adb keyevent 26 / notification shade during Patrol
      // instrumentation crashes the process on API 34 AVDs. Lockscreen FSI
      // best-effort coverage lives in screenshot_flow_test companions.
      // Here we grant USE_FULL_SCREEN_INTENT via adb and assert the in-app
      // ring surface after the alarm callback.
      // -------------------------------------------------------------------
      await grantFullScreenIntentViaAdb();
      await $(FloatingActionButton).tap();
      await pumpFrames($.tester);
      await $(TextField).first.enterText('FSI Ring Routine');
      await $('Save').tap();
      await pumpUntilFound(
        $.tester,
        find.text('FSI Ring Routine'),
        timeout: const Duration(seconds: 15),
      );

      final fsiRoutines = await database.watchAllRoutines().first;
      final fsiRoutine = fsiRoutines.firstWhere(
        (r) => r.Name == 'FSI Ring Routine',
      );

      await RA_AlarmService.simulateAlarmCallback(fsiRoutine.Id);
      await pumpUntilFound(
        $.tester,
        find.byType(AlarmRingPage),
        timeout: const Duration(seconds: 12),
      );
      expect($(AlarmRingPage), findsOneWidget);
      expect($('Slide to snooze'), findsOneWidget);
      expect($('Slide to dismiss'), findsOneWidget);

      final fsiRinging = await database.getRoutineState(fsiRoutine.Id);
      expect(fsiRinging!.IsRinging, isTrue);
      expect(fsiRinging.InitialRingTime, isNotNull);

      await slideToDismiss($.tester);
      await _waitForRingGone($, database, fsiRoutine.Id);
      final fsiAfter = await database.getRoutineState(fsiRoutine.Id);
      expect(fsiAfter!.IsRinging, isFalse);
      expect(fsiAfter.NextTriggerTime, isNotNull);

      // -------------------------------------------------------------------
      // 3) Interval math: snooze / auto-snooze / dismiss / restart / isolate
      // -------------------------------------------------------------------
      await $(FloatingActionButton).tap();
      await pumpFrames($.tester);
      await $(TextField).first.enterText('InitialRing Lifecycle');
      await $('Save').tap();
      await pumpUntilFound(
        $.tester,
        find.text('InitialRing Lifecycle'),
        timeout: const Duration(seconds: 15),
      );

      final routines = await database.watchAllRoutines().first;
      final initialRingRoutine = routines.firstWhere(
        (r) => r.Name == 'InitialRing Lifecycle',
      );
      expect(
        DriftCompensationTypeCodeEnum.values[initialRingRoutine
            .DriftCompensationTypeCode],
        DriftCompensationTypeCodeEnum.InitialRing,
      );

      await RA_AlarmService.simulateAlarmCallback(initialRingRoutine.Id);
      await pumpUntilFound($.tester, find.byType(AlarmRingPage));

      final firstRingState = await database.getRoutineState(
        initialRingRoutine.Id,
      );
      final preservedInitialRing = firstRingState!.InitialRingTime!;
      expect(firstRingState.IsRinging, isTrue);
      expect(firstRingState.CurrentSnoozeCount, 0);

      final snoozeAt = DateTime.now();
      await slideToSnooze($.tester);
      await _waitForRingGone($, database, initialRingRoutine.Id);

      final afterUiSnooze = await database.getRoutineState(
        initialRingRoutine.Id,
      );
      expect(afterUiSnooze!.IsRinging, isFalse);
      expect(afterUiSnooze.CurrentSnoozeCount, 1);
      expect(afterUiSnooze.InitialRingTime, equals(preservedInitialRing));

      final expectedSnoozeTrigger = snoozeAt.add(
        Duration(seconds: initialRingRoutine.SnoozeSeconds),
      );
      expect(
        afterUiSnooze.NextTriggerTime!
                .difference(expectedSnoozeTrigger)
                .inSeconds
                .abs() <=
            2,
        isTrue,
        reason: 'UI snooze must schedule now + SnoozeSeconds',
      );

      final isolateDb = RA_Database.openForIsolate(dbPath);
      try {
        final isolateView = await isolateDb.getRoutineState(
          initialRingRoutine.Id,
        );
        expect(isolateView!.CurrentSnoozeCount, 1);
        expect(
          isolateView.NextTriggerTime,
          equals(afterUiSnooze.NextTriggerTime),
        );
        expect(isolateView.InitialRingTime, equals(preservedInitialRing));
      } finally {
        await isolateDb.close();
      }

      await _simulateAppRestart($, dbPath: dbPath, database: database);
      await pumpUntilFound($.tester, find.text('InitialRing Lifecycle'));

      final afterRestart = await database.getRoutineState(
        initialRingRoutine.Id,
      );
      expect(afterRestart!.CurrentSnoozeCount, 1);
      expect(
        afterRestart.NextTriggerTime,
        equals(afterUiSnooze.NextTriggerTime),
      );

      await RA_AlarmService.simulateAlarmCallback(initialRingRoutine.Id);
      await pumpUntilFound($.tester, find.byType(AlarmRingPage));
      final reRing = await database.getRoutineState(initialRingRoutine.Id);
      expect(reRing!.CurrentSnoozeCount, 1);
      expect(reRing.InitialRingTime, equals(preservedInitialRing));

      await RA_AlarmService.simulateWatchdogCallback(initialRingRoutine.Id);
      await pumpUntilCondition(
        $.tester,
        () async {
          final s = await database.getRoutineState(initialRingRoutine.Id);
          return s != null && !s.IsRinging && s.CurrentSnoozeCount == 2;
        },
      );

      final afterAutoSnooze = await database.getRoutineState(
        initialRingRoutine.Id,
      );
      expect(afterAutoSnooze!.CurrentSnoozeCount, 2);
      expect(afterAutoSnooze.InitialRingTime, equals(preservedInitialRing));

      await RA_AlarmService.simulateAlarmCallback(initialRingRoutine.Id);
      await pumpUntilFound($.tester, find.byType(AlarmRingPage));
      await slideToDismiss($.tester);
      await _waitForRingGone($, database, initialRingRoutine.Id);

      final dismissed = await database.getRoutineState(initialRingRoutine.Id);
      expect(dismissed!.IsRinging, isFalse);
      expect(dismissed.CurrentSnoozeCount, 0);
      expect(dismissed.LastDismissedAt, isNotNull);

      final expectedInitialRingNext = RA_AlarmCalculator.calculateNextTrigger(
        Action: RA_AlarmActionTypeCodeEnum.Dismiss,
        Compensation: DriftCompensationTypeCodeEnum.InitialRing,
        IntervalSeconds: initialRingRoutine.IntervalSeconds,
        SnoozeSeconds: initialRingRoutine.SnoozeSeconds,
        InitialRingTime: preservedInitialRing,
        Now: DateTime.now(),
      );
      expect(dismissed.NextTriggerTime, equals(expectedInitialRingNext));

      final logs = await database.getAllLogEntries();
      final routineLogs = logs
          .where((l) => l.RoutineId == initialRingRoutine.Id)
          .toList();
      expect(
        routineLogs.any(
          (l) => l.LogActionTypeCode == LogActionTypeCodeEnum.Snooze.index,
        ),
        isTrue,
      );
      expect(
        routineLogs.any(
          (l) => l.LogActionTypeCode == LogActionTypeCodeEnum.AutoSnooze.index,
        ),
        isTrue,
      );
      expect(
        routineLogs.any(
          (l) => l.LogActionTypeCode == LogActionTypeCodeEnum.Dismiss.index,
        ),
        isTrue,
      );

      // ActualDismissal: next trigger follows dismiss wall clock
      await $(FloatingActionButton).tap();
      await pumpFrames($.tester);
      await $(TextField).first.enterText('ActualDismissal Lifecycle');
      await $('Actual Dismissal').scrollTo();
      await $('Actual Dismissal').tap();
      await $('Save').tap();
      await pumpUntilFound(
        $.tester,
        find.text('ActualDismissal Lifecycle'),
        timeout: const Duration(seconds: 15),
      );

      final routinesAfter = await database.watchAllRoutines().first;
      final actualDismissalRoutine = routinesAfter.firstWhere(
        (r) => r.Name == 'ActualDismissal Lifecycle',
      );
      expect(
        DriftCompensationTypeCodeEnum.values[actualDismissalRoutine
            .DriftCompensationTypeCode],
        DriftCompensationTypeCodeEnum.ActualDismissal,
      );

      await RA_AlarmService.simulateAlarmCallback(actualDismissalRoutine.Id);
      await pumpUntilFound($.tester, find.byType(AlarmRingPage));
      final actualFirstRing = await database.getRoutineState(
        actualDismissalRoutine.Id,
      );
      final actualInitialRing = actualFirstRing!.InitialRingTime!;

      await slideToSnooze($.tester);
      await _waitForRingGone($, database, actualDismissalRoutine.Id);

      await RA_AlarmService.simulateAlarmCallback(actualDismissalRoutine.Id);
      await pumpUntilFound($.tester, find.byType(AlarmRingPage));

      final dismissAt = DateTime.now();
      await slideToDismiss($.tester);
      await _waitForRingGone($, database, actualDismissalRoutine.Id);

      final actualDismissed = await database.getRoutineState(
        actualDismissalRoutine.Id,
      );
      expect(actualDismissed!.IsRinging, isFalse);
      expect(actualDismissed.CurrentSnoozeCount, 0);

      final expectedActualNext = RA_AlarmCalculator.calculateNextTrigger(
        Action: RA_AlarmActionTypeCodeEnum.Dismiss,
        Compensation: DriftCompensationTypeCodeEnum.ActualDismissal,
        IntervalSeconds: actualDismissalRoutine.IntervalSeconds,
        SnoozeSeconds: actualDismissalRoutine.SnoozeSeconds,
        InitialRingTime: actualInitialRing,
        Now: dismissAt,
      );

      expect(
        actualDismissed.NextTriggerTime!
                .difference(expectedActualNext)
                .inSeconds
                .abs() <=
            2,
        isTrue,
        reason:
            'ActualDismissal must base the next interval on dismiss time, '
            'not InitialRingTime ($actualInitialRing)',
      );

      final initialRingFormula = RA_AlarmCalculator.calculateNextTrigger(
        Action: RA_AlarmActionTypeCodeEnum.Dismiss,
        Compensation: DriftCompensationTypeCodeEnum.InitialRing,
        IntervalSeconds: actualDismissalRoutine.IntervalSeconds,
        SnoozeSeconds: actualDismissalRoutine.SnoozeSeconds,
        InitialRingTime: actualInitialRing,
        Now: dismissAt,
      );
      expect(
        initialRingFormula,
        equals(
          actualInitialRing.add(
            Duration(seconds: actualDismissalRoutine.IntervalSeconds),
          ),
        ),
      );
    },
  );
}
