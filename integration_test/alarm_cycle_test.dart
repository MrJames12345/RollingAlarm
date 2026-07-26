import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/alarm_action_type_code.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';
import 'package:rolling_alarm/main.dart';
import 'package:rolling_alarm/pages/alarm_ring.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/alarm_calculator.dart';
import 'package:rolling_alarm/services/notification.dart';

import 'helpers/android_alarm_test_helpers.dart';
import 'helpers/e2e_pump_helpers.dart';

void main() {
  patrolTest(
    'Rolling Alarm E2E alarm cycle: exact alarm grant, ring, dismiss, recalculate',
    ($) async {
      configureIntegrationTestDrift();
      installKnownUiErrorFilter();

      final dbPath = await RA_Database.resolveDatabasePath();
      final database = RA_Database();
      registerTestUiPort(database);
      await RA_AlarmService.init();
      await RA_NotificationService.init();

      await $.pumpWidget(
        ProviderScope(
          overrides: [
            RA_DatabaseProvider.overrideWithValue(database),
          ],
          child: RollingAlarmApp(dbPath: dbPath),
        ),
      );
      await pumpFrames($.tester);

      await ensureScheduleExactAlarmAllowed($);
      await pumpFrames($.tester);

      expect($('Rolling Alarm'), findsOneWidget);

      await $(FloatingActionButton).tap();
      await pumpFrames($.tester);

      await $(TextField).first.enterText('Cycle Test Routine');
      await $('Save').tap();
      await pumpUntilFound(
        $.tester,
        find.text('Cycle Test Routine'),
        timeout: const Duration(seconds: 15),
      );

      expect($('Cycle Test Routine'), findsOneWidget);

      final routines = await database.watchAllRoutines().first;
      final routine = routines.firstWhere((r) => r.Name == 'Cycle Test Routine');
      final before = await database.getRoutineState(routine.Id);
      expect(before?.NextTriggerTime, isNotNull);

      await RA_AlarmService.simulateAlarmCallback(routine.Id);
      await pumpUntilFound($.tester, find.byType(AlarmRingPage));

      expect($(AlarmRingPage), findsOneWidget);
      expect($('Slide to dismiss'), findsOneWidget);

      final ringing = await database.getRoutineState(routine.Id);
      final initialRing = ringing!.InitialRingTime!;
      expect(ringing.IsRinging, isTrue);

      await slideToDismiss($.tester);
      await pumpUntilGone($.tester, find.byType(AlarmRingPage));

      expect($(AlarmRingPage), findsNothing);
      expect($('Cycle Test Routine'), findsOneWidget);

      final after = await database.getRoutineState(routine.Id);
      expect(after!.IsRinging, isFalse);
      expect(after.CurrentSnoozeCount, 0);
      expect(after.LastDismissedAt, isNotNull);

      final expected = RA_AlarmCalculator.calculateNextTrigger(
        Action: RA_AlarmActionTypeCodeEnum.Dismiss,
        Compensation: DriftCompensationTypeCodeEnum.values[
            routine.DriftCompensationTypeCode],
        IntervalSeconds: routine.IntervalSeconds,
        SnoozeSeconds: routine.SnoozeSeconds,
        InitialRingTime: initialRing,
        Now: after.LastDismissedAt!,
      );
      expect(after.NextTriggerTime, equals(expected));
    },
  );
}
