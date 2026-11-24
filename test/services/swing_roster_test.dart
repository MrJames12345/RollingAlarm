import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/alarm_action_type_code.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/daily_ring_limit.dart';
import 'package:rolling_alarm/services/swing_roster.dart';
import 'package:rolling_alarm/services/weekday_schedule.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

    const alarmChannel = MethodChannel(
      'dev.fluttercommunity.plus/android_alarm_manager',
      JSONMethodCodec(),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(alarmChannel, (MethodCall call) async => true);

    const uiSchedulerChannel = MethodChannel(
      'com.casellaweb.rolling_alarm/alarm_ui_scheduler',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          uiSchedulerChannel,
          (MethodCall call) async => true,
        );

    const notifChannel = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifChannel, (MethodCall call) async => true);

    const homeWidgetChannel = MethodChannel('home_widget');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          homeWidgetChannel,
          (MethodCall call) async => true,
        );
  });

  group('RA_SwingRosterSchedule', () {
    // 2026-06-01 is a Monday.
    final anchorDate = DateTime(2026, 6, 1);
    final anchorEpochDay = RA_SwingRosterSchedule.localEpochDay(anchorDate);
    const fiveAm = 5 * 3600;
    const sixAm = 6 * 3600;
    const fiveThirtyPm = 17 * 3600 + 30 * 60;

    test('8/6 FIFO rollover activates Days 1..8 ON, defers Days 9..14 OFF to Day 15 at DayStartSeconds', () {
      // Days 0..7 (Jun 1 .. Jun 8) are ON.
      for (var d = 0; d < 8; d++) {
        final proposed = DateTime(2026, 6, 1 + d, 10, 0);
        expect(
          RA_SwingRosterSchedule.isOnSwing(
            proposed,
            cycleOnDays: 8,
            cycleOffDays: 6,
            cycleAnchorEpochDay: anchorEpochDay,
            dayStartSeconds: fiveAm,
          ),
          isTrue,
          reason: 'Day ${d + 1} of 8/6 should be ON',
        );
        expect(
          RA_SwingRosterSchedule.deferToActiveDay(
            proposed,
            enabledWeekdays: RA_WeekdaySchedule.allDaysMask,
            dayStartSeconds: fiveAm,
            cycleOnDays: 8,
            cycleOffDays: 6,
            cycleAnchorEpochDay: anchorEpochDay,
          ),
          equals(proposed),
        );
      }

      // Badge on Day 3 (Jun 3) reads "8/6 Swing · Day 3 of 8 ON".
      final day3Status = RA_SwingRosterSchedule.statusAt(
        now: DateTime(2026, 6, 3, 9, 0),
        cycleOnDays: 8,
        cycleOffDays: 6,
        cycleAnchorEpochDay: anchorEpochDay,
        dayStartSeconds: fiveAm,
      );
      expect(day3Status, isNotNull);
      expect(day3Status!.isOnSwing, isTrue);
      expect(day3Status.badgeLabel, equals('8/6 Swing · Day 3 of 8 ON'));

      // Days 8..13 (Jun 9 .. Jun 14) are OFF and all defer to Jun 15 05:00.
      final expectedNextOn = DateTime(2026, 6, 15, 5, 0);
      for (var d = 8; d < 14; d++) {
        final proposed = DateTime(2026, 6, 1 + d, 11, 30);
        expect(
          RA_SwingRosterSchedule.isOnSwing(
            proposed,
            cycleOnDays: 8,
            cycleOffDays: 6,
            cycleAnchorEpochDay: anchorEpochDay,
            dayStartSeconds: fiveAm,
          ),
          isFalse,
          reason: 'Day ${d + 1} of 8/6 should be OFF',
        );
        expect(
          RA_SwingRosterSchedule.deferToActiveDay(
            proposed,
            enabledWeekdays: RA_WeekdaySchedule.allDaysMask,
            dayStartSeconds: fiveAm,
            cycleOnDays: 8,
            cycleOffDays: 6,
            cycleAnchorEpochDay: anchorEpochDay,
          ),
          equals(expectedNextOn),
        );
      }

      // Off-swing badge shows next Mon 5:00 AM.
      final offStatus = RA_SwingRosterSchedule.statusAt(
        now: DateTime(2026, 6, 10, 9, 0),
        cycleOnDays: 8,
        cycleOffDays: 6,
        cycleAnchorEpochDay: anchorEpochDay,
        dayStartSeconds: fiveAm,
      );
      expect(offStatus, isNotNull);
      expect(offStatus!.isOnSwing, isFalse);
      expect(
        offStatus.badgeLabel,
        equals('R&R Off-Swing · Starts Mon 5:00 AM'),
      );

      // Day 15 (Jun 15) starts the next ON swing.
      final day15 = DateTime(2026, 6, 15, 5, 0);
      expect(
        RA_SwingRosterSchedule.isOnSwing(
          day15,
          cycleOnDays: 8,
          cycleOffDays: 6,
          cycleAnchorEpochDay: anchorEpochDay,
          dayStartSeconds: fiveAm,
        ),
        isTrue,
      );
    });

    test('4-on / 4-off nursing rollover cycles cleanly across multiple periods', () {
      // Jun 1..4 ON, Jun 5..8 OFF, Jun 9..12 ON, Jun 13..16 OFF.
      expect(
        RA_SwingRosterSchedule.deferToActiveDay(
          DateTime(2026, 6, 4, 18, 0),
          enabledWeekdays: RA_WeekdaySchedule.allDaysMask,
          dayStartSeconds: sixAm,
          cycleOnDays: 4,
          cycleOffDays: 4,
          cycleAnchorEpochDay: anchorEpochDay,
        ),
        equals(DateTime(2026, 6, 4, 18, 0)),
      );
      // Jun 5 (Fri, Day 1 OFF) defers to Jun 9 (Tue) 6:00 AM!
      expect(
        RA_SwingRosterSchedule.deferToActiveDay(
          DateTime(2026, 6, 5, 6, 0),
          enabledWeekdays: RA_WeekdaySchedule.allDaysMask,
          dayStartSeconds: sixAm,
          cycleOnDays: 4,
          cycleOffDays: 4,
          cycleAnchorEpochDay: anchorEpochDay,
        ),
        equals(DateTime(2026, 6, 9, 6, 0)),
      );
      final offStatus = RA_SwingRosterSchedule.statusAt(
        now: DateTime(2026, 6, 6, 8, 0),
        cycleOnDays: 4,
        cycleOffDays: 4,
        cycleAnchorEpochDay: anchorEpochDay,
        dayStartSeconds: sixAm,
      );
      expect(
        offStatus!.badgeLabel,
        equals('R&R Off-Swing · Starts Tue 6:00 AM'),
      );
      // Jun 13 (Day 13 = pos 4 OFF) defers to Jun 17 6:00 AM.
      expect(
        RA_SwingRosterSchedule.deferToActiveDay(
          DateTime(2026, 6, 13, 12, 0),
          enabledWeekdays: RA_WeekdaySchedule.allDaysMask,
          dayStartSeconds: sixAm,
          cycleOnDays: 4,
          cycleOffDays: 4,
          cycleAnchorEpochDay: anchorEpochDay,
        ),
        equals(DateTime(2026, 6, 17, 6, 0)),
      );
    });

    test('night-shift DayStartSeconds respects logical day boundary after midnight', () {
      // 2/1 night swing (14 on / 7 off) anchored Jun 1 at 5:30 PM.
      // Jun 14 is Day 14 ON (period Jun 14 17:30 -> Jun 15 17:30).
      // Jun 15 at 02:00 AM still belongs to Jun 14's ON night shift!
      final lastNightShiftEarlyAm = DateTime(2026, 6, 15, 2, 0);
      expect(
        RA_SwingRosterSchedule.isOnSwing(
          lastNightShiftEarlyAm,
          cycleOnDays: 14,
          cycleOffDays: 7,
          cycleAnchorEpochDay: anchorEpochDay,
          dayStartSeconds: fiveThirtyPm,
        ),
        isTrue,
      );

      // Jun 15 at 17:30 starts Day 1 OFF -> defers 7 days to Jun 22 17:30.
      final firstOffShiftStart = DateTime(2026, 6, 15, 17, 30);
      expect(
        RA_SwingRosterSchedule.deferToActiveDay(
          firstOffShiftStart,
          enabledWeekdays: RA_WeekdaySchedule.allDaysMask,
          dayStartSeconds: fiveThirtyPm,
          cycleOnDays: 14,
          cycleOffDays: 7,
          cycleAnchorEpochDay: anchorEpochDay,
        ),
        equals(DateTime(2026, 6, 22, 17, 30)),
      );

      // Jun 22 at 03:00 AM belongs to Jun 21 (last OFF day) -> defers cleanly
      // to Jun 22 17:30 (14.5h later) instead of firing prematurely at 03:00 AM.
      expect(
        RA_SwingRosterSchedule.deferToActiveDay(
          DateTime(2026, 6, 22, 3, 0),
          enabledWeekdays: RA_WeekdaySchedule.allDaysMask,
          dayStartSeconds: fiveThirtyPm,
          cycleOnDays: 14,
          cycleOffDays: 7,
          cycleAnchorEpochDay: anchorEpochDay,
        ),
        equals(DateTime(2026, 6, 22, 17, 30)),
      );
    });

    test('future anchor wraps cleanly with Euclidean modulo and intersects with enabledWeekdays', () {
      // Anchor 3 days in the future (Jun 4) on 8/6 -> Jun 1 is delta=-3 -> pos=11 (OFF),
      // so Jun 1 defers to Jun 4 at 06:00.
      final futureAnchor = RA_SwingRosterSchedule.localEpochDay(
        DateTime(2026, 6, 4),
      );
      expect(
        RA_SwingRosterSchedule.deferToActiveDay(
          DateTime(2026, 6, 1, 9, 0),
          enabledWeekdays: RA_WeekdaySchedule.allDaysMask,
          dayStartSeconds: sixAm,
          cycleOnDays: 8,
          cycleOffDays: 6,
          cycleAnchorEpochDay: futureAnchor,
        ),
        equals(DateTime(2026, 6, 4, 6, 0)),
      );

      // Joint intersection: 4/4 anchored Mon Jun 1 (Mon-Thu ON), weekday mask = Sunday only (1 << 6).
      // First Sunday that is also ON-swing is Jun 28 (delta = 27 -> 27 % 8 = 3 ON!).
      const sundayOnly = 1 << 6;
      expect(
        RA_SwingRosterSchedule.hasIntersectingActiveDay(
          cycleOnDays: 4,
          cycleOffDays: 4,
          cycleAnchorEpochDay: anchorEpochDay,
          enabledWeekdays: sundayOnly,
        ),
        isTrue,
      );
      expect(
        RA_SwingRosterSchedule.deferToActiveDay(
          DateTime(2026, 6, 1, 9, 0),
          enabledWeekdays: sundayOnly,
          dayStartSeconds: sixAm,
          cycleOnDays: 4,
          cycleOffDays: 4,
          cycleAnchorEpochDay: anchorEpochDay,
        ),
        equals(DateTime(2026, 6, 28, 6, 0)),
      );

      // Impossible intersection: 3 On / 4 Off anchored Mon Jun 1 (Mon-Wed ON)
      // paired with Thu-Fri only (bits 3 & 4). No day can ever satisfy both.
      const thuFriOnly = (1 << 3) | (1 << 4);
      expect(
        RA_SwingRosterSchedule.hasIntersectingActiveDay(
          cycleOnDays: 3,
          cycleOffDays: 4,
          cycleAnchorEpochDay: anchorEpochDay,
          enabledWeekdays: thuFriOnly,
        ),
        isFalse,
      );
      final impossibleOffStatus = RA_SwingRosterSchedule.statusAt(
        now: DateTime(2026, 6, 4, 9, 0), // Thu (OFF-swing)
        cycleOnDays: 3,
        cycleOffDays: 4,
        cycleAnchorEpochDay: anchorEpochDay,
        dayStartSeconds: sixAm,
        enabledWeekdays: thuFriOnly,
      );
      expect(impossibleOffStatus, isNotNull);
      expect(impossibleOffStatus!.isOnSwing, isFalse);
      expect(impossibleOffStatus.nextOnSwingStart, isNull);
      expect(
        impossibleOffStatus.badgeLabel,
        equals('R&R Off-Swing · Day 1 of 4 OFF'),
      );
    });

    test('integrates with RA_DailyRingLimit.initialTriggerTime and retargetNextAfterEdit', () {
      // Creating an 8/6 routine during OFF-swing (Jun 10) defers initial trigger to Jun 15 05:00.
      final initial = RA_DailyRingLimit.initialTriggerTime(
        now: DateTime(2026, 6, 10, 9, 0),
        interval: const Duration(hours: 12),
        maxTimesPerDayEnabled: true,
        dayStartSeconds: fiveAm,
        cycleOnDays: 8,
        cycleOffDays: 6,
        cycleAnchorEpochDay: anchorEpochDay,
      );
      expect(initial, equals(DateTime(2026, 6, 15, 5, 0)));

      // Disabling swing roster while parked on Jun 15 05:00 unparks to tomorrow 05:00 (Jun 11).
      final unparked = RA_DailyRingLimit.retargetNextAfterEdit(
        previousNext: DateTime(2026, 6, 15, 5, 0),
        oldDayStartSeconds: fiveAm,
        newDayStartSeconds: fiveAm,
        oldMaxTimesPerDayEnabled: true,
        newMaxTimesPerDayEnabled: true,
        oldMaxTimesPerDay: 1,
        newMaxTimesPerDay: 1,
        timesRingToday: 0,
        timesRingDay: null,
        now: DateTime(2026, 6, 10, 9, 0),
        intervalSeconds: 43200,
        enabledWeekdays: RA_WeekdaySchedule.allDaysMask,
        oldCycleOnDays: 8,
        newCycleOnDays: 0,
        oldCycleOffDays: 6,
        newCycleOffDays: 0,
        oldCycleAnchorEpochDay: anchorEpochDay,
        newCycleAnchorEpochDay: null,
      );
      expect(unparked, equals(DateTime(2026, 6, 11, 5, 0)));
    });

    test('RA_AlarmService suppresses ring on OFF-swing day and defers to next ON swing', () async {
      final tempDir = await Directory.systemTemp.createTemp('ra_swing_cb_');
      final dbPath = p.join(tempDir.path, 'swing.db');
      SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

      final now = DateTime.now();
      // Anchor 9 days ago on an 8/6 cycle -> today is Day 2 of OFF-swing (pos = 9 >= 8).
      final offAnchor =
          RA_SwingRosterSchedule.localEpochDay(now) - 9;

      final db = RA_Database.openForIsolate(dbPath);
      try {
        final routineId = await db.insertRoutineWithInitialState(
          routine: RoutinesCompanion(
            Name: const Value('FIFO Off-Swing Guard'),
            IntervalSeconds: const Value(43200),
            SnoozeSeconds: const Value(600),
            DayStartSeconds: const Value(5 * 3600),
            CycleOnDays: const Value(8),
            CycleOffDays: const Value(6),
            CycleAnchorEpochDay: Value(offAnchor),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
          ),
          nextTriggerTime: now,
        );
        await db.close();

        await RA_AlarmService.simulateAlarmCallback(routineId);

        final verifyDb = RA_Database.openForIsolate(dbPath);
        try {
          final state = await verifyDb.getRoutineState(routineId);
          expect(state, isNotNull);
          expect(state!.IsRinging, isFalse);
          expect(state.NextTriggerTime, isNotNull);
          expect(state.NextTriggerTime!.isAfter(now), isTrue);

          final routine = await verifyDb.getRoutineById(routineId);
          final nextForDismiss = RA_AlarmService.nextTriggerForAction(
            action: RA_AlarmActionTypeCodeEnum.Dismiss,
            routine: routine,
            state: state,
            now: now,
          );
          expect(
            RA_SwingRosterSchedule.isOnSwing(
              nextForDismiss,
              cycleOnDays: 8,
              cycleOffDays: 6,
              cycleAnchorEpochDay: offAnchor,
              dayStartSeconds: 5 * 3600,
            ),
            isTrue,
          );
        } finally {
          await verifyDb.close();
        }
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });
}
