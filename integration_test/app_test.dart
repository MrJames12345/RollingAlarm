import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/main.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/notification.dart';

import 'helpers/android_alarm_test_helpers.dart';
import 'helpers/e2e_pump_helpers.dart';

void main() {
  patrolTest(
    'Rolling Alarm E2E flow: create routine, schedule near-immediate alarm, dismiss',
    ($) async {
      configureIntegrationTestDrift();
      installKnownUiErrorFilter();

      // 1. Initialise services & DB for test
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

      // 2. Runtime permissions plus SCHEDULE_EXACT_ALARM (native attempt, adb fallback)
      await ensureScheduleExactAlarmAllowed($);
      await pumpFrames($.tester);

      // 3. Verify Home page loads
      expect($('Rolling Alarm'), findsOneWidget);

      // 4. Tap the FloatingActionButton to create a new routine
      await $(FloatingActionButton).tap();
      await pumpFrames($.tester);

      // 5. Enter routine name
      await $(TextField).first.enterText('E2E Test Routine');

      // 6. Save routine
      await $('Save').tap();
      await pumpUntilFound(
        $.tester,
        find.text('E2E Test Routine'),
        timeout: const Duration(seconds: 15),
      );

      // 7. Verify routine appears on Home Page
      expect($('E2E Test Routine'), findsOneWidget);

      // 8. Long-press the tile and reset the interval from the menu
      await $('E2E Test Routine').longPress();
      await pumpFrames($.tester);
      expect($('Dismiss Early'), findsOneWidget);
      await $('Dismiss Early').tap();
      await pumpFrames($.tester);
    },
  );
}
