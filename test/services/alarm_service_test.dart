import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/alarm_action_type_code.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';
import 'package:rolling_alarm/enums/log_action_type_code.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/audio.dart';
import 'package:rolling_alarm/services/daily_ring_limit.dart';
import 'package:rolling_alarm/services/notification.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockDatabase extends Mock implements RA_Database {
  /// Drift's generic [transaction] is awkward to stub with mocktail; run the
  /// action inline so handleTransition CAS tests still verify update/log calls.
  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) {
    return action();
  }

  /// Forward to [insertLogEntry] so activity helpers work with the same stubs.
  @override
  Future<int> insertActivityLog({
    required int routineId,
    required LogActionTypeCodeEnum action,
    DateTime? timestamp,
  }) {
    return insertLogEntry(
      LogEntriesCompanion(
        RoutineId: Value(routineId),
        Timestamp: Value(timestamp ?? DateTime.now()),
        LogActionTypeCode: Value(action.index),
      ),
    );
  }
}

class FakeRoutineStatesCompanion extends Fake
    implements RoutineStatesCompanion {}

class FakeLogEntriesCompanion extends Fake implements LogEntriesCompanion {}

void main() {
  final alarmChannelCalls = <MethodCall>[];
  final uiSchedulerChannelCalls = <MethodCall>[];
  final notifChannelCalls = <MethodCall>[];
  var mockIgnoringBatteryOptimizations = true;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(FakeRoutineStatesCompanion());
    registerFallbackValue(FakeLogEntriesCompanion());

    // Mock AndroidAlarmManager method channel
    const channel = MethodChannel(
      'dev.fluttercommunity.plus/android_alarm_manager',
      JSONMethodCodec(),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          alarmChannelCalls.add(methodCall);
          return true;
        });

    const uiSchedulerChannel = MethodChannel(
      'com.casellaweb.rolling_alarm/alarm_ui_scheduler',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(uiSchedulerChannel, (
          MethodCall methodCall,
        ) async {
          uiSchedulerChannelCalls.add(methodCall);
          if (methodCall.method == 'isIgnoringBatteryOptimizations') {
            return mockIgnoringBatteryOptimizations;
          }
          if (methodCall.method == 'requestIgnoreBatteryOptimizations') {
            return true;
          }
          if (methodCall.method == 'ensureIgnoringBatteryOptimizations') {
            return true;
          }
          return null;
        });

    // Mock local notifications and home widget method channels
    const notifChannel = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifChannel, (MethodCall methodCall) async {
          notifChannelCalls.add(methodCall);
          if (methodCall.method == 'canUseFullScreenIntent') {
            return true;
          }
          return true;
        });

    const homeWidgetChannel = MethodChannel('home_widget');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          homeWidgetChannel,
          (MethodCall methodCall) async => true,
        );

    const alarmSoundChannel = MethodChannel(
      'com.casellaweb.rolling_alarm/alarm_sound',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(alarmSoundChannel, (
          MethodCall methodCall,
        ) async {
          if (methodCall.method == 'getSystemAlarmVolume') {
            return 1.0;
          }
          return null;
        });
  });

  group('RA_AlarmService Plugin Boundary Tests', () {
    late MockDatabase mockDb;

    setUp(() {
      mockDb = MockDatabase();
      SharedPreferences.setMockInitialValues({});
      alarmChannelCalls.clear();
      uiSchedulerChannelCalls.clear();
      notifChannelCalls.clear();
      mockIgnoringBatteryOptimizations = true;
    });

    test(
      'handleTransition Dismiss updates RoutineState to IsRinging=false and logs Dismiss',
      () async {
        final now = DateTime.now();
        final routine = RoutineModel(
          Id: 1,
          Name: 'Test Alarm',
          SnoozeSeconds: 540,
          IntervalSeconds: 14400,
          MaxTimesPerDayEnabled: false,
          MaxTimesPerDay: 0,
          DayStartSeconds: 0,
          EnabledWeekdays: 0x7F,
          CycleOnDays: 0,
          CycleOffDays: 0,
          CycleAnchorEpochDay: null,
          DriftCompensationTypeCode:
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
          ShowPreview: true,
          Vibrate: true,
          Volume: 100,
          FadeIn: false,
          AudioUri: null,
          IsActive: true,
          CreatedAt: now,
          ModifiedAt: null,
          Deleted: false,
        );

        final state = RoutineStateModel(
          Id: 10,
          RoutineId: 1,
          NextTriggerTime: now,
          InitialRingTime: now,
          IsRinging: true,
          CurrentSnoozeCount: 0,
          TimesRingToday: 0,
          ExtraMaxTimesToday: 0,
          TimesRingDay: null,
          LastDismissedAt: null,
          CreatedAt: now,
          ModifiedAt: null,
          Deleted: false,
        );

        when(
          () => mockDb.getRoutineState(routine.Id),
        ).thenAnswer((_) async => state);
        when(
          () => mockDb.updateRoutineState(
            any(),
            any(),
            requireIsRinging: any(named: 'requireIsRinging'),
            matchNextTriggerTime: any(named: 'matchNextTriggerTime'),
            nextTriggerTimeToMatch: any(named: 'nextTriggerTimeToMatch'),
          ),
        ).thenAnswer((_) async => 1);
        when(() => mockDb.insertLogEntry(any())).thenAnswer((_) async => 1);

        await RA_AlarmService.handleTransition(
          action: RA_AlarmActionTypeCodeEnum.Dismiss,
          routineId: routine.Id,
          db: mockDb,
          routine: routine,
          state: state,
        );

        // Verify state update was called with CAS requireIsRinging=true
        verify(
          () => mockDb.updateRoutineState(
            routine.Id,
            any(
              that: predicate<RoutineStatesCompanion>((companion) {
                return companion.IsRinging.value == false &&
                    companion.CurrentSnoozeCount.value == 0;
              }),
            ),
            requireIsRinging: true,
            matchNextTriggerTime: false,
            nextTriggerTimeToMatch: null,
          ),
        ).called(1);

        // Verify log entry was inserted
        verify(
          () => mockDb.insertLogEntry(
            any(
              that: predicate<LogEntriesCompanion>((companion) {
                return companion.RoutineId.value == routine.Id &&
                    companion.LogActionTypeCode.value ==
                        LogActionTypeCodeEnum.Dismiss.index;
              }),
            ),
          ),
        ).called(1);
      },
    );

    test(
      'handleTransition Snooze increments CurrentSnoozeCount and logs Snooze',
      () async {
        final now = DateTime.now();
        final routine = RoutineModel(
          Id: 2,
          Name: 'Snooze Alarm',
          SnoozeSeconds: 600,
          IntervalSeconds: 28800,
          MaxTimesPerDayEnabled: false,
          MaxTimesPerDay: 0,
          DayStartSeconds: 0,
          EnabledWeekdays: 0x7F,
          CycleOnDays: 0,
          CycleOffDays: 0,
          CycleAnchorEpochDay: null,
          DriftCompensationTypeCode:
              DriftCompensationTypeCodeEnum.InitialRing.index,
          ShowPreview: true,
          Vibrate: true,
          Volume: 100,
          FadeIn: false,
          AudioUri: null,
          IsActive: true,
          CreatedAt: now,
          ModifiedAt: null,
          Deleted: false,
        );

        final state = RoutineStateModel(
          Id: 20,
          RoutineId: 2,
          NextTriggerTime: now,
          InitialRingTime: now,
          IsRinging: true,
          CurrentSnoozeCount: 1,
          TimesRingToday: 0,
          ExtraMaxTimesToday: 0,
          TimesRingDay: null, // already snoozed once
          LastDismissedAt: null,
          CreatedAt: now,
          ModifiedAt: null,
          Deleted: false,
        );

        when(
          () => mockDb.getRoutineState(routine.Id),
        ).thenAnswer((_) async => state);
        when(
          () => mockDb.updateRoutineState(
            any(),
            any(),
            requireIsRinging: any(named: 'requireIsRinging'),
            matchNextTriggerTime: any(named: 'matchNextTriggerTime'),
            nextTriggerTimeToMatch: any(named: 'nextTriggerTimeToMatch'),
          ),
        ).thenAnswer((_) async => 1);
        when(() => mockDb.insertLogEntry(any())).thenAnswer((_) async => 1);

        await RA_AlarmService.handleTransition(
          action: RA_AlarmActionTypeCodeEnum.Snooze,
          routineId: routine.Id,
          db: mockDb,
          routine: routine,
          state: state,
        );

        verify(
          () => mockDb.updateRoutineState(
            routine.Id,
            any(
              that: predicate<RoutineStatesCompanion>((companion) {
                return companion.IsRinging.value == false &&
                    companion.CurrentSnoozeCount.value == 2; // Incremented to 2
              }),
            ),
            requireIsRinging: true,
            matchNextTriggerTime: false,
            nextTriggerTimeToMatch: null,
          ),
        ).called(1);

        verify(
          () => mockDb.insertLogEntry(
            any(
              that: predicate<LogEntriesCompanion>((companion) {
                return companion.LogActionTypeCode.value ==
                    LogActionTypeCodeEnum.Snooze.index;
              }),
            ),
          ),
        ).called(1);
      },
    );

    test(
      'handleTransition aborts Dismiss when IsRinging was already cleared',
      () async {
        final now = DateTime.now();
        final routine = RoutineModel(
          Id: 4,
          Name: 'Race Alarm',
          SnoozeSeconds: 540,
          IntervalSeconds: 14400,
          MaxTimesPerDayEnabled: false,
          MaxTimesPerDay: 0,
          DayStartSeconds: 0,
          EnabledWeekdays: 0x7F,
          CycleOnDays: 0,
          CycleOffDays: 0,
          CycleAnchorEpochDay: null,
          DriftCompensationTypeCode:
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
          ShowPreview: true,
          Vibrate: true,
          Volume: 100,
          FadeIn: false,
          AudioUri: null,
          IsActive: true,
          CreatedAt: now,
          ModifiedAt: null,
          Deleted: false,
        );

        final ringingState = RoutineStateModel(
          Id: 40,
          RoutineId: 4,
          NextTriggerTime: now,
          InitialRingTime: now,
          IsRinging: true,
          CurrentSnoozeCount: 0,
          TimesRingToday: 0,
          ExtraMaxTimesToday: 0,
          TimesRingDay: null,
          LastDismissedAt: null,
          CreatedAt: now,
          ModifiedAt: null,
          Deleted: false,
        );

        final alreadyCleared = ringingState.copyWith(IsRinging: false);

        // MockDatabase.transaction runs the action inline; re-read sees cleared ring.
        when(
          () => mockDb.getRoutineState(routine.Id),
        ).thenAnswer((_) async => alreadyCleared);

        await RA_AlarmService.handleTransition(
          action: RA_AlarmActionTypeCodeEnum.Dismiss,
          routineId: routine.Id,
          db: mockDb,
          routine: routine,
          state: ringingState,
        );

        verifyNever(
          () => mockDb.updateRoutineState(
            any(),
            any(),
            requireIsRinging: any(named: 'requireIsRinging'),
            matchNextTriggerTime: any(named: 'matchNextTriggerTime'),
            nextTriggerTimeToMatch: any(named: 'nextTriggerTimeToMatch'),
          ),
        );
        verifyNever(() => mockDb.insertLogEntry(any()));
      },
    );

    test(
      'scheduleNext passes exact, wakeup, allowWhileIdle, and rescheduleOnReboot to oneShotAt without alarmClock',
      () async {
        await RA_AlarmService.scheduleNext(
          routineId: 99,
          triggerTime: DateTime.now().add(const Duration(hours: 1)),
          dbPath: '/tmp/test.db',
          routineName: 'Test Routine',
        );

        final oneShotCalls = alarmChannelCalls
            .where((c) => c.method == 'Alarm.oneShotAt')
            .toList();
        expect(oneShotCalls, isNotEmpty);

        // android_alarm_manager_plus packs args as:
        // [id, alarmClock, allowWhileIdle, exact, wakeup, startMillis,
        //  rescheduleOnReboot, handle, params]
        final args = oneShotCalls.last.arguments as List<dynamic>;
        expect(args[0], equals(1000 + 99));
        expect(args[1], isFalse); // native setAlarmClock is the sole AlarmClock
        expect(args[2], isTrue); // allowWhileIdle
        expect(args[3], isTrue); // exact
        expect(args[4], isTrue); // wakeup
        expect(args[6], isTrue); // rescheduleOnReboot

        alarmChannelCalls.clear();
        await RA_AlarmService.cancel(99);
        final cancelCalls = alarmChannelCalls
            .where((c) => c.method == 'Alarm.cancel')
            .toList();
        expect(cancelCalls.length, greaterThanOrEqualTo(1));

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('ra_db_path'), '/tmp/test.db');
      },
    );

    test('handleTransition Skip resets snooze count and logs Skip', () async {
      final now = DateTime.now();
      final routine = RoutineModel(
        Id: 3,
        Name: 'Skip Alarm',
        SnoozeSeconds: 540,
        IntervalSeconds: 16200,
        MaxTimesPerDayEnabled: false,
        MaxTimesPerDay: 0,
        DayStartSeconds: 0,
        EnabledWeekdays: 0x7F,
        CycleOnDays: 0,
        CycleOffDays: 0,
        CycleAnchorEpochDay: null,
        DriftCompensationTypeCode:
            DriftCompensationTypeCodeEnum.InitialRing.index,
        ShowPreview: true,
        Vibrate: true,
        Volume: 100,
        FadeIn: false,
        AudioUri: null,
        IsActive: true,
        CreatedAt: now,
        ModifiedAt: null,
        Deleted: false,
      );

      final state = RoutineStateModel(
        Id: 30,
        RoutineId: 3,
        NextTriggerTime: now,
        InitialRingTime: now.subtract(const Duration(minutes: 5)),
        IsRinging: false,
        CurrentSnoozeCount: 2,
        TimesRingToday: 0,
        ExtraMaxTimesToday: 0,
        TimesRingDay: null,
        LastDismissedAt: now.subtract(const Duration(hours: 4)),
        CreatedAt: now,
        ModifiedAt: null,
        Deleted: false,
      );

      when(
        () => mockDb.getRoutineState(routine.Id),
      ).thenAnswer((_) async => state);
      when(
        () => mockDb.updateRoutineState(
          any(),
          any(),
          requireIsRinging: any(named: 'requireIsRinging'),
          matchNextTriggerTime: any(named: 'matchNextTriggerTime'),
          nextTriggerTimeToMatch: any(named: 'nextTriggerTimeToMatch'),
        ),
      ).thenAnswer((_) async => 1);
      when(() => mockDb.insertLogEntry(any())).thenAnswer((_) async => 1);

      await RA_AlarmService.handleTransition(
        action: RA_AlarmActionTypeCodeEnum.Skip,
        routineId: routine.Id,
        db: mockDb,
        routine: routine,
        state: state,
      );

      // Idle Skip locks on NextTriggerTime so concurrent Skips cannot both win.
      verify(
        () => mockDb.updateRoutineState(
          routine.Id,
          any(
            that: predicate<RoutineStatesCompanion>((companion) {
              return companion.IsRinging.value == false &&
                  companion.CurrentSnoozeCount.value == 0 &&
                  companion.LastDismissedAt.present &&
                  !companion.TimesRingToday.present;
            }),
          ),
          requireIsRinging: null,
          matchNextTriggerTime: true,
          nextTriggerTimeToMatch: now,
        ),
      ).called(1);

      verify(
        () => mockDb.insertLogEntry(
          any(
            that: predicate<LogEntriesCompanion>((companion) {
              return companion.LogActionTypeCode.value ==
                      LogActionTypeCodeEnum.Skip.index &&
                  companion.TimeSinceLastDismissalSeconds.present;
            }),
          ),
        ),
      ).called(1);
    });

    test(
      'handleTransition Skip with countSkipTowardsDaily increments TimesRingToday',
      () async {
        final now = DateTime.now();
        final routine = RoutineModel(
          Id: 4,
          Name: 'Count Skip',
          SnoozeSeconds: 300,
          IntervalSeconds: 7200,
          MaxTimesPerDayEnabled: false,
          MaxTimesPerDay: 0,
          DayStartSeconds: 0,
          EnabledWeekdays: 0x7F,
          CycleOnDays: 0,
          CycleOffDays: 0,
          CycleAnchorEpochDay: null,
          DriftCompensationTypeCode:
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
          ShowPreview: true,
          Vibrate: true,
          Volume: 100,
          FadeIn: false,
          AudioUri: null,
          IsActive: true,
          CreatedAt: now,
          ModifiedAt: null,
          Deleted: false,
        );

        final state = RoutineStateModel(
          Id: 40,
          RoutineId: 4,
          NextTriggerTime: now.add(const Duration(minutes: 10)),
          InitialRingTime: null,
          IsRinging: false,
          CurrentSnoozeCount: 0,
          TimesRingToday: 2,
          ExtraMaxTimesToday: 0,
          TimesRingDay: RA_DailyRingLimit.periodStart(now, 0),
          LastDismissedAt: null,
          CreatedAt: now,
          ModifiedAt: null,
          Deleted: false,
        );

        when(
          () => mockDb.getRoutineState(routine.Id),
        ).thenAnswer((_) async => state);
        when(
          () => mockDb.updateRoutineState(
            any(),
            any(),
            requireIsRinging: any(named: 'requireIsRinging'),
            matchNextTriggerTime: any(named: 'matchNextTriggerTime'),
            nextTriggerTimeToMatch: any(named: 'nextTriggerTimeToMatch'),
          ),
        ).thenAnswer((_) async => 1);
        when(() => mockDb.insertLogEntry(any())).thenAnswer((_) async => 1);

        await RA_AlarmService.handleTransition(
          action: RA_AlarmActionTypeCodeEnum.Skip,
          routineId: routine.Id,
          db: mockDb,
          routine: routine,
          state: state,
          countSkipTowardsDaily: true,
        );

        verify(
          () => mockDb.updateRoutineState(
            routine.Id,
            any(
              that: predicate<RoutineStatesCompanion>((companion) {
                return companion.TimesRingToday.present &&
                    companion.TimesRingToday.value == 3 &&
                    companion.TimesRingDay.present;
              }),
            ),
            requireIsRinging: null,
            matchNextTriggerTime: true,
            nextTriggerTimeToMatch: state.NextTriggerTime,
          ),
        ).called(1);
      },
    );

    test(
      'RA_NotificationService showAlarmNotification never posts a local notification',
      () async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        addTearDown(() {
          debugDefaultTargetPlatformOverride = previousPlatform;
        });

        SharedPreferences.setMockInitialValues({});
        await RA_NotificationService.init();
        notifChannelCalls.clear();
        await RA_NotificationService.showAlarmNotification(
          routineId: 1,
          routineName: 'Morning Alarm',
        );

        final showCalls = notifChannelCalls
            .where((c) => c.method == 'show')
            .toList();
        expect(showCalls, isEmpty);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(RA_NotificationService.ringingPrefKey), isTrue);
        expect(
          prefs.getInt(RA_NotificationService.alarmWakeAtPrefKey),
          isNotNull,
        );

        await RA_NotificationService.cancelNotification(1);
        final cancelCalls = notifChannelCalls
            .where((c) => c.method == 'cancel')
            .toList();
        expect(cancelCalls, isNotEmpty);
        expect(prefs.getBool(RA_NotificationService.ringingPrefKey), isFalse);
      },
    );

    test(
      'notification dismiss action applies transition against a real db file',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_notif_');
        final dbPath = p.join(tempDir.path, 'test.db');
        SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

        final db = RA_Database.openForIsolate(dbPath);
        final now = DateTime.now();
        final routineId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Notif Routine'),
            IntervalSeconds: const Value(14400),
            SnoozeSeconds: const Value(540),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            ShowPreview: const Value(true),
            IsActive: const Value(true),
          ),
        );
        await db.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            NextTriggerTime: Value(now),
            InitialRingTime: Value(now),
            IsRinging: const Value(true),
            CurrentSnoozeCount: const Value(0),
          ),
        );
        await db.close();

        await RA_NotificationService.handleNotificationResponse(
          NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotificationAction,
            id: routineId,
            actionId: 'dismiss',
            payload: routineId.toString(),
          ),
        );

        final verifyDb = RA_Database.openForIsolate(dbPath);
        final state = await verifyDb.getRoutineState(routineId);
        final logs = await verifyDb.getAllLogEntries();
        expect(state!.IsRinging, isFalse);
        expect(state.CurrentSnoozeCount, 0);
        expect(logs, isNotEmpty);
        expect(
          logs.first.LogActionTypeCode,
          LogActionTypeCodeEnum.Dismiss.index,
        );
        await verifyDb.close();
        await tempDir.delete(recursive: true);
      },
    );

    test(
      'handleTransition serializes concurrent dismiss and auto-snooze on one ring',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_race_');
        final dbPath = p.join(tempDir.path, 'test.db');
        SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

        final seedDb = RA_Database.openForIsolate(dbPath);
        final now = DateTime.now();
        final routineId = await seedDb.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Race Routine'),
            IntervalSeconds: const Value(14400),
            SnoozeSeconds: const Value(540),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            IsActive: const Value(true),
          ),
        );
        await seedDb.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            NextTriggerTime: Value(now),
            InitialRingTime: Value(now),
            IsRinging: const Value(true),
            CurrentSnoozeCount: const Value(0),
          ),
        );
        final routine = await seedDb.getRoutineById(routineId);
        final state = (await seedDb.getRoutineState(routineId))!;
        await seedDb.close();

        final db = RA_Database.openForIsolate(dbPath);
        await Future.wait([
          RA_AlarmService.handleTransition(
            action: RA_AlarmActionTypeCodeEnum.Dismiss,
            routineId: routineId,
            db: db,
            routine: routine,
            state: state,
          ),
          RA_AlarmService.handleTransition(
            action: RA_AlarmActionTypeCodeEnum.AutoSnooze,
            routineId: routineId,
            db: db,
            routine: routine,
            state: state,
          ),
        ]);

        final after = await db.getRoutineState(routineId);
        final logs = await db.getAllLogEntries();
        expect(after!.IsRinging, isFalse);
        // Exactly one transition commits; the loser aborts on IsRinging=false.
        expect(logs.length, equals(1));
        expect(
          logs.first.LogActionTypeCode,
          anyOf(
            LogActionTypeCodeEnum.Dismiss.index,
            LogActionTypeCodeEnum.AutoSnooze.index,
          ),
        );
        await db.close();
        await tempDir.delete(recursive: true);
      },
    );

    test(
      'handleTransition CAS on a second connection loses after the first clears IsRinging',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_cross_conn_');
        final dbPath = p.join(tempDir.path, 'test.db');
        SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

        final seedDb = RA_Database.openForIsolate(dbPath);
        final now = DateTime.now();
        final routineId = await seedDb.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Cross Conn Race'),
            IntervalSeconds: const Value(14400),
            SnoozeSeconds: const Value(540),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            IsActive: const Value(true),
          ),
        );
        await seedDb.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            NextTriggerTime: Value(now),
            InitialRingTime: Value(now),
            IsRinging: const Value(true),
            CurrentSnoozeCount: const Value(0),
          ),
        );
        final routine = await seedDb.getRoutineById(routineId);
        final state = (await seedDb.getRoutineState(routineId))!;
        await seedDb.close();

        // Two connections (UI vs alarm) without same-isolate concurrent
        // BEGIN IMMEDIATE, which would busy-wait deadlock on one thread.
        final uiDb = RA_Database.openForIsolate(dbPath);
        final alarmDb = RA_Database.openForIsolate(dbPath);

        await RA_AlarmService.handleTransition(
          action: RA_AlarmActionTypeCodeEnum.Dismiss,
          routineId: routineId,
          db: uiDb,
          routine: routine,
          state: state,
        );
        await RA_AlarmService.handleTransition(
          action: RA_AlarmActionTypeCodeEnum.AutoSnooze,
          routineId: routineId,
          db: alarmDb,
          routine: routine,
          state: state,
        );

        final after = await uiDb.getRoutineState(routineId);
        final logs = await uiDb.getAllLogEntries();
        expect(after!.IsRinging, isFalse);
        expect(logs.length, equals(1));
        expect(
          logs.first.LogActionTypeCode,
          LogActionTypeCodeEnum.Dismiss.index,
        );
        await uiDb.close();
        await alarmDb.close();
        await tempDir.delete(recursive: true);
      },
    );

    test(
      'simulateAlarmCallback after snooze preserves InitialRingTime and CurrentSnoozeCount',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_alarm_cb_');
        final dbPath = p.join(tempDir.path, 'test.db');
        SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

        final seedDb = RA_Database.openForIsolate(dbPath);
        final initialRing = DateTime(2026, 1, 1, 6, 0, 0);
        final routineId = await seedDb.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Preserve State Alarm'),
            IntervalSeconds: const Value(16200),
            SnoozeSeconds: const Value(540),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.InitialRing.index,
            ),
            IsActive: const Value(true),
          ),
        );
        await seedDb.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            NextTriggerTime: Value(initialRing.add(const Duration(minutes: 9))),
            InitialRingTime: Value(initialRing),
            IsRinging: const Value(false),
            CurrentSnoozeCount: const Value(2),
          ),
        );
        await seedDb.close();

        await RA_AlarmService.simulateAlarmCallback(routineId);

        final verifyDb = RA_Database.openForIsolate(dbPath);
        final after = await verifyDb.getRoutineState(routineId);
        expect(after, isNotNull);
        expect(after!.IsRinging, isTrue);
        expect(after.CurrentSnoozeCount, equals(2));
        expect(after.InitialRingTime, equals(initialRing));
        await verifyDb.close();
        await tempDir.delete(recursive: true);
      },
    );

    test(
      'simulateAlarmCallback on fresh cycle records InitialRingTime and resets snooze count',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'ra_alarm_fresh_',
        );
        final dbPath = p.join(tempDir.path, 'test.db');
        SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

        final seedDb = RA_Database.openForIsolate(dbPath);
        final routineId = await seedDb.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Fresh Cycle Alarm'),
            IntervalSeconds: const Value(14400),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            IsActive: const Value(true),
          ),
        );
        await seedDb.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            NextTriggerTime: Value(DateTime(2026, 1, 1, 10, 0, 0)),
            InitialRingTime: Value(DateTime(2026, 1, 1, 6, 0, 0)),
            IsRinging: const Value(false),
            CurrentSnoozeCount: const Value(0),
          ),
        );
        await seedDb.close();

        await RA_AlarmService.simulateAlarmCallback(routineId);

        final verifyDb = RA_Database.openForIsolate(dbPath);
        final state = await verifyDb.getRoutineState(routineId);
        expect(state, isNotNull);
        expect(state!.IsRinging, isTrue);
        expect(state.CurrentSnoozeCount, equals(0));
        expect(state.InitialRingTime, isNotNull);
        // Fresh cycle must replace the stale prior-cycle InitialRingTime.
        expect(
          state.InitialRingTime,
          isNot(equals(DateTime(2026, 1, 1, 6, 0, 0))),
        );
        await verifyDb.close();
        await tempDir.delete(recursive: true);
      },
    );

    test('simulateWatchdogCallback auto-snoozes a ringing routine', () async {
      final tempDir = await Directory.systemTemp.createTemp('ra_watchdog_');
      final dbPath = p.join(tempDir.path, 'test.db');
      SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

      final seedDb = RA_Database.openForIsolate(dbPath);
      final initialRing = DateTime(2026, 1, 1, 6, 0, 0);
      final routineId = await seedDb.insertRoutine(
        RoutinesCompanion(
          Name: const Value('Watchdog Alarm'),
          IntervalSeconds: const Value(14400),
          SnoozeSeconds: const Value(540),
          DriftCompensationTypeCode: Value(
            DriftCompensationTypeCodeEnum.ActualDismissal.index,
          ),
          IsActive: const Value(true),
        ),
      );
      await seedDb.insertRoutineState(
        RoutineStatesCompanion(
          RoutineId: Value(routineId),
          NextTriggerTime: Value(initialRing),
          InitialRingTime: Value(initialRing),
          IsRinging: const Value(true),
          CurrentSnoozeCount: const Value(0),
        ),
      );
      await seedDb.close();

      await RA_AlarmService.simulateWatchdogCallback(routineId);

      final verifyDb = RA_Database.openForIsolate(dbPath);
      final state = await verifyDb.getRoutineState(routineId);
      final logs = await verifyDb.getAllLogEntries();
      expect(state, isNotNull);
      expect(state!.IsRinging, isFalse);
      expect(state.CurrentSnoozeCount, equals(1));
      expect(state.NextTriggerTime, isNotNull);
      expect(logs, isNotEmpty);
      expect(
        logs.first.LogActionTypeCode,
        LogActionTypeCodeEnum.AutoSnooze.index,
      );
      await verifyDb.close();
      await tempDir.delete(recursive: true);
    });

    test(
      'reconcileAlarmsOnStartup re-arms active routines with a NextTriggerTime',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_reconcile_');
        final dbPath = p.join(tempDir.path, 'test.db');
        SharedPreferences.setMockInitialValues({});
        alarmChannelCalls.clear();

        final seedDb = RA_Database.openForIsolate(dbPath);
        final routineId = await seedDb.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Reconcile Alarm'),
            IntervalSeconds: const Value(14400),
            SnoozeSeconds: const Value(540),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            IsActive: const Value(true),
          ),
        );
        final next = DateTime.now().add(const Duration(hours: 2));
        await seedDb.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            NextTriggerTime: Value(next),
            IsRinging: const Value(false),
            CurrentSnoozeCount: const Value(0),
          ),
        );
        await seedDb.close();

        final reconcileDb = RA_Database.openForIsolate(dbPath);
        await RA_AlarmService.reconcileAlarmsOnStartup(
          db: reconcileDb,
          dbPath: dbPath,
        );
        await reconcileDb.close();

        final oneShotCalls = alarmChannelCalls
            .where((c) => c.method == 'Alarm.oneShotAt')
            .toList();
        expect(oneShotCalls, isNotEmpty);
        final args = oneShotCalls.last.arguments as List<dynamic>;
        expect(args[0], equals(1000 + routineId));
        expect(args[6], isTrue); // rescheduleOnReboot

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('ra_db_path'), dbPath);

        await tempDir.delete(recursive: true);
      },
    );

    test('persistDatabasePath writes ra_db_path for isolate openers', () async {
      SharedPreferences.setMockInitialValues({});
      const path = '/tmp/rolling_alarm_persist_test.db';
      await RA_AlarmService.persistDatabasePath(path);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ra_db_path'), path);
    });

    test(
      'reconcileAlarmsOnStartup while IsRinging cancels then re-arms watchdog',
      () async {
        alarmChannelCalls.clear();
        final tempDir = await Directory.systemTemp.createTemp(
          'ra_reconcile_ring_',
        );
        final dbPath = p.join(tempDir.path, 'test.db');
        SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

        final seedDb = RA_Database.openForIsolate(dbPath);
        final routineId = await seedDb.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Ringing Reconcile'),
            IntervalSeconds: const Value(14400),
            SnoozeSeconds: const Value(540),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            IsActive: const Value(true),
          ),
        );
        await seedDb.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            IsRinging: const Value(true),
            CurrentSnoozeCount: const Value(0),
          ),
        );
        await seedDb.close();

        final reconcileDb = RA_Database.openForIsolate(dbPath);
        await RA_AlarmService.reconcileAlarmsOnStartup(
          db: reconcileDb,
          dbPath: dbPath,
        );
        await reconcileDb.close();

        final cancelCalls = alarmChannelCalls
            .where((c) => c.method == 'Alarm.cancel')
            .toList();
        final oneShotCalls = alarmChannelCalls
            .where((c) => c.method == 'Alarm.oneShotAt')
            .toList();
        expect(cancelCalls, isNotEmpty);
        expect(oneShotCalls, isNotEmpty);
        final watchdogArgs = oneShotCalls.last.arguments as List<dynamic>;
        expect(watchdogArgs[0], equals(5000 + routineId));

        await tempDir.delete(recursive: true);
      },
    );

    test(
      'duplicate simulateAlarmCallback does not reset InitialRingTime or re-notify',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_dup_alarm_');
        final dbPath = p.join(tempDir.path, 'test.db');
        SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

        final seedDb = RA_Database.openForIsolate(dbPath);
        final routineId = await seedDb.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Dup Alarm'),
            IntervalSeconds: const Value(14400),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            IsActive: const Value(true),
          ),
        );
        await seedDb.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            NextTriggerTime: Value(DateTime(2026, 1, 1, 10, 0, 0)),
            IsRinging: const Value(false),
            CurrentSnoozeCount: const Value(0),
          ),
        );
        await seedDb.close();

        await RA_AlarmService.simulateAlarmCallback(routineId);
        final midDb = RA_Database.openForIsolate(dbPath);
        final afterFirst = await midDb.getRoutineState(routineId);
        expect(afterFirst!.IsRinging, isTrue);
        final initialRing = afterFirst.InitialRingTime;
        expect(initialRing, isNotNull);
        await midDb.close();

        // OS duplicate delivery while already ringing must be a no-op.
        await RA_AlarmService.simulateAlarmCallback(routineId);

        final verifyDb = RA_Database.openForIsolate(dbPath);
        final afterSecond = await verifyDb.getRoutineState(routineId);
        expect(afterSecond!.IsRinging, isTrue);
        expect(afterSecond.InitialRingTime, equals(initialRing));
        expect(afterSecond.CurrentSnoozeCount, equals(0));
        await verifyDb.close();
        await tempDir.delete(recursive: true);
      },
    );

    test(
      'concurrent idle Skip on separate connections commits exactly once',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_skip_race_');
        final dbPath = p.join(tempDir.path, 'test.db');
        SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

        final seedDb = RA_Database.openForIsolate(dbPath);
        final now = DateTime.now();
        final next = now.add(const Duration(hours: 2));
        final routineId = await seedDb.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Skip Race'),
            IntervalSeconds: const Value(14400),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            IsActive: const Value(true),
          ),
        );
        await seedDb.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            NextTriggerTime: Value(next),
            IsRinging: const Value(false),
            CurrentSnoozeCount: const Value(0),
            LastDismissedAt: Value(now.subtract(const Duration(hours: 4))),
          ),
        );
        final routine = await seedDb.getRoutineById(routineId);
        final state = (await seedDb.getRoutineState(routineId))!;
        await seedDb.close();

        final uiDb = RA_Database.openForIsolate(dbPath);
        final widgetDb = RA_Database.openForIsolate(dbPath);

        await RA_AlarmService.handleTransition(
          action: RA_AlarmActionTypeCodeEnum.Skip,
          routineId: routineId,
          db: uiDb,
          routine: routine,
          state: state,
        );
        await RA_AlarmService.handleTransition(
          action: RA_AlarmActionTypeCodeEnum.Skip,
          routineId: routineId,
          db: widgetDb,
          routine: routine,
          state: state,
        );

        final after = await uiDb.getRoutineState(routineId);
        final logs = await uiDb.getAllLogEntries();
        expect(after!.IsRinging, isFalse);
        expect(after.NextTriggerTime, isNot(equals(next)));
        expect(logs.length, equals(1));
        expect(logs.first.LogActionTypeCode, LogActionTypeCodeEnum.Skip.index);
        await uiDb.close();
        await widgetDb.close();
        await tempDir.delete(recursive: true);
      },
    );

    test(
      'pauseRoutine freezes remaining countdown; resumeRoutine shifts NextTriggerTime',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_pause_');
        final dbPath = p.join(tempDir.path, 'test.db');
        SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

        final db = RA_Database.openForIsolate(dbPath);
        final now = DateTime.now();
        final next = now.add(const Duration(minutes: 30));
        final routineId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Pause Routine'),
            IntervalSeconds: const Value(14400),
            SnoozeSeconds: const Value(300),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            IsActive: const Value(true),
          ),
        );
        await db.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            NextTriggerTime: Value(next),
          ),
        );
        final routine = await db.getRoutineById(routineId);

        await RA_AlarmService.pauseRoutine(
          routineId: routineId,
          db: db,
          routine: routine,
          dbPath: dbPath,
        );

        final pausedRoutine = await db.getRoutineById(routineId);
        final pausedState = await db.getRoutineState(routineId);
        expect(pausedRoutine.IsActive, isFalse);
        expect(pausedState!.PausedAt, isNotNull);
        expect(pausedState.NextTriggerTime, isNotNull);
        expect(pausedState.IsRinging, isFalse);

        final frozenSeconds = pausedState.NextTriggerTime!
            .difference(pausedState.PausedAt!)
            .inSeconds;
        final expectedSeconds = next.difference(DateTime.now()).inSeconds;
        // Frozen digits match the live floor(remaining) at pause time (+/- 1s
        // for the async gap between capturing now and asserting).
        expect(frozenSeconds, closeTo(expectedSeconds, 2));
        expect(frozenSeconds, closeTo(30 * 60, 5));

        await Future<void>.delayed(const Duration(milliseconds: 50));

        await RA_AlarmService.resumeRoutine(
          routineId: routineId,
          db: db,
          routine: pausedRoutine,
          dbPath: dbPath,
        );

        final resumedRoutine = await db.getRoutineById(routineId);
        final resumedState = await db.getRoutineState(routineId);
        expect(resumedRoutine.IsActive, isTrue);
        expect(resumedState!.PausedAt, isNull);
        expect(resumedState.NextTriggerTime, isNotNull);
        final remaining = resumedState.NextTriggerTime!.difference(
          DateTime.now(),
        );
        expect(remaining.inSeconds, closeTo(frozenSeconds, 2));

        await db.close();
        await tempDir.delete(recursive: true);
      },
    );

    test(
      'pause at day-start keeps absolute NextTriggerTime; resume before it unchanged',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_pause_ds_');
        final dbPath = p.join(tempDir.path, 'test.db');
        SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

        final db = RA_Database.openForIsolate(dbPath);
        const dayStartSeconds = 6 * 3600;
        final now = DateTime.now();
        final dayStart = RA_DailyRingLimit.nextPeriodStartAfter(
          now,
          dayStartSeconds,
        );
        final routineId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Day Start Pause'),
            IntervalSeconds: const Value(14400),
            SnoozeSeconds: const Value(300),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            MaxTimesPerDayEnabled: const Value(true),
            MaxTimesPerDay: const Value(3),
            DayStartSeconds: const Value(dayStartSeconds),
            IsActive: const Value(true),
          ),
        );
        await db.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            NextTriggerTime: Value(dayStart),
            TimesRingToday: const Value(3),
            TimesRingDay: Value(
              RA_DailyRingLimit.periodStart(now, dayStartSeconds),
            ),
          ),
        );
        final routine = await db.getRoutineById(routineId);

        await RA_AlarmService.pauseRoutine(
          routineId: routineId,
          db: db,
          routine: routine,
          dbPath: dbPath,
        );

        final pausedState = await db.getRoutineState(routineId);
        expect(pausedState!.PausedAt, isNotNull);
        expect(
          pausedState.NextTriggerTime!.millisecondsSinceEpoch,
          dayStart.millisecondsSinceEpoch,
        );

        await Future<void>.delayed(const Duration(milliseconds: 50));

        await RA_AlarmService.resumeRoutine(
          routineId: routineId,
          db: db,
          routine: routine,
          dbPath: dbPath,
        );

        final resumed = await db.getRoutineState(routineId);
        expect(resumed!.PausedAt, isNull);
        expect(
          resumed.NextTriggerTime!.millisecondsSinceEpoch,
          dayStart.millisecondsSinceEpoch,
        );
        expect((await db.getRoutineById(routineId)).IsActive, isTrue);

        await db.close();
        await tempDir.delete(recursive: true);
      },
    );

    test(
      'resetTodayCounter unparks day-start when prior count hit the daily cap',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_reset_cap_');
        final dbPath = p.join(tempDir.path, 'test.db');
        SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

        final db = RA_Database.openForIsolate(dbPath);
        const dayStartSeconds = 6 * 3600;
        const intervalSeconds = 4 * 3600;
        final before = DateTime.now();
        final dayStart = RA_DailyRingLimit.nextPeriodStartAfter(
          before,
          dayStartSeconds,
        );
        final routineId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Reset Cap Park'),
            IntervalSeconds: const Value(intervalSeconds),
            SnoozeSeconds: const Value(300),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            MaxTimesPerDayEnabled: const Value(true),
            MaxTimesPerDay: const Value(3),
            DayStartSeconds: const Value(dayStartSeconds),
            IsActive: const Value(true),
          ),
        );
        await db.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            NextTriggerTime: Value(dayStart),
            TimesRingToday: const Value(3),
            TimesRingDay: Value(
              RA_DailyRingLimit.periodStart(before, dayStartSeconds),
            ),
          ),
        );
        final routine = await db.getRoutineById(routineId);

        await RA_AlarmService.resetTodayCounter(
          routineId: routineId,
          db: db,
          routine: routine,
          dbPath: dbPath,
        );

        final after = DateTime.now();
        final state = await db.getRoutineState(routineId);
        expect(state!.TimesRingToday, equals(0));
        expect(state.NextTriggerTime, isNotNull);
        expect(
          state.NextTriggerTime!.millisecondsSinceEpoch,
          isNot(equals(dayStart.millisecondsSinceEpoch)),
        );
        // Resumed to roughly now + interval (allow a few seconds of skew).
        final delta = state.NextTriggerTime!.difference(before).inSeconds;
        expect(delta, closeTo(intervalSeconds, 5));
        expect(
          state.NextTriggerTime!.isAfter(
            after.subtract(const Duration(seconds: 2)),
          ),
          isTrue,
        );
        expect(
          alarmChannelCalls.any((c) => c.method == 'Alarm.oneShotAt'),
          isTrue,
        );

        await db.close();
        await tempDir.delete(recursive: true);
      },
    );

    test(
      'resetTodayCounter zeros count only when not parked for the daily cap',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_reset_keep_');
        final dbPath = p.join(tempDir.path, 'test.db');
        SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

        final db = RA_Database.openForIsolate(dbPath);
        const dayStartSeconds = 6 * 3600;
        final now = DateTime.now();
        final next = now.add(const Duration(hours: 2));
        final routineId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Reset Keep Next'),
            IntervalSeconds: const Value(14400),
            SnoozeSeconds: const Value(300),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            MaxTimesPerDayEnabled: const Value(true),
            MaxTimesPerDay: const Value(5),
            DayStartSeconds: const Value(dayStartSeconds),
            IsActive: const Value(true),
          ),
        );
        await db.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            NextTriggerTime: Value(next),
            TimesRingToday: const Value(2),
            TimesRingDay: Value(
              RA_DailyRingLimit.periodStart(now, dayStartSeconds),
            ),
          ),
        );
        final routine = await db.getRoutineById(routineId);

        await RA_AlarmService.resetTodayCounter(
          routineId: routineId,
          db: db,
          routine: routine,
          dbPath: dbPath,
        );

        final state = await db.getRoutineState(routineId);
        expect(state!.TimesRingToday, equals(0));
        // Drift stores whole Unix seconds; compare second precision only.
        expect(
          state.NextTriggerTime!.millisecondsSinceEpoch ~/ 1000,
          next.millisecondsSinceEpoch ~/ 1000,
        );
        expect(
          alarmChannelCalls.any((c) => c.method == 'Alarm.oneShotAt'),
          isFalse,
        );

        await db.close();
        await tempDir.delete(recursive: true);
      },
    );

    test(
      'resume after missed day-start uses earliest of interval and next day-start',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_pause_miss_');
        final dbPath = p.join(tempDir.path, 'test.db');
        SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

        final db = RA_Database.openForIsolate(dbPath);
        const dayStartSeconds = 6 * 3600;
        const intervalSeconds = 14400;
        final resumeAnchor = DateTime.now();
        final pausedAt = resumeAnchor.subtract(const Duration(days: 2));
        final missedDayStart = RA_DailyRingLimit.nextPeriodStartAfter(
          pausedAt,
          dayStartSeconds,
        );
        expect(missedDayStart.isBefore(resumeAnchor), isTrue);

        final routineId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Missed Day Start'),
            IntervalSeconds: const Value(intervalSeconds),
            SnoozeSeconds: const Value(300),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            MaxTimesPerDayEnabled: const Value(true),
            MaxTimesPerDay: const Value(3),
            DayStartSeconds: const Value(dayStartSeconds),
            IsActive: const Value(false),
          ),
        );
        await db.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            NextTriggerTime: Value(missedDayStart),
            PausedAt: Value(pausedAt),
          ),
        );
        final routine = await db.getRoutineById(routineId);

        await RA_AlarmService.resumeRoutine(
          routineId: routineId,
          db: db,
          routine: routine,
          dbPath: dbPath,
        );

        final resumed = await db.getRoutineState(routineId);
        final expected = RA_DailyRingLimit.earliestResumeAfterMissedDayStart(
          now: DateTime.now(),
          intervalSeconds: intervalSeconds,
          dayStartSeconds: dayStartSeconds,
        );
        expect(resumed!.PausedAt, isNull);
        expect(
          resumed.NextTriggerTime!.difference(expected).inSeconds.abs(),
          lessThanOrEqualTo(2),
        );

        await db.close();
        await tempDir.delete(recursive: true);
      },
    );

    test(
      'muteRoutine keeps schedule active; pause clears mute; mute clears pause',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_mute_');
        final dbPath = p.join(tempDir.path, 'test.db');
        SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

        final db = RA_Database.openForIsolate(dbPath);
        final now = DateTime.now();
        final next = DateTime.fromMillisecondsSinceEpoch(
          ((now.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000) *
              1000),
        );
        final routineId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Mute Routine'),
            IntervalSeconds: const Value(14400),
            SnoozeSeconds: const Value(300),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            IsActive: const Value(true),
          ),
        );
        await db.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            NextTriggerTime: Value(next),
          ),
        );
        final routine = await db.getRoutineById(routineId);

        await RA_AlarmService.muteRoutine(
          routineId: routineId,
          db: db,
          routine: routine,
          dbPath: dbPath,
        );

        var state = await db.getRoutineState(routineId);
        expect((await db.getRoutineById(routineId)).IsActive, isTrue);
        expect(state!.MutedAt, isNotNull);
        expect(state.PausedAt, isNull);
        expect(
          state.NextTriggerTime!.millisecondsSinceEpoch,
          next.millisecondsSinceEpoch,
        );

        await RA_AlarmService.pauseRoutine(
          routineId: routineId,
          db: db,
          routine: routine,
          dbPath: dbPath,
        );
        state = await db.getRoutineState(routineId);
        expect(state!.MutedAt, isNull);
        expect(state.PausedAt, isNotNull);
        expect((await db.getRoutineById(routineId)).IsActive, isFalse);

        await RA_AlarmService.muteRoutine(
          routineId: routineId,
          db: db,
          routine: await db.getRoutineById(routineId),
          dbPath: dbPath,
        );
        state = await db.getRoutineState(routineId);
        expect(state!.MutedAt, isNotNull);
        expect(state.PausedAt, isNull);
        expect((await db.getRoutineById(routineId)).IsActive, isTrue);
        // Resume-from-pause then mute shifts the frozen remaining forward.
        expect(state.NextTriggerTime, isNotNull);
        expect(state.NextTriggerTime!.isAfter(DateTime.now()), isTrue);

        await RA_AlarmService.unmuteRoutine(routineId: routineId, db: db);
        state = await db.getRoutineState(routineId);
        expect(state!.MutedAt, isNull);

        await db.close();
        await tempDir.delete(recursive: true);
      },
    );

    test(
      'muted fire increments TimesRingToday without lasting IsRinging',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_mute_fire_');
        final dbPath = p.join(tempDir.path, 'test.db');
        SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

        final db = RA_Database.openForIsolate(dbPath);
        final now = DateTime.now();
        final routineId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Muted Fire'),
            IntervalSeconds: const Value(3600),
            SnoozeSeconds: const Value(300),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            MaxTimesPerDayEnabled: const Value(true),
            MaxTimesPerDay: const Value(5),
            IsActive: const Value(true),
          ),
        );
        await db.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            NextTriggerTime: Value(now),
            MutedAt: Value(now.subtract(const Duration(minutes: 1))),
            TimesRingToday: const Value(1),
            TimesRingDay: Value(RA_DailyRingLimit.periodStart(now, 0)),
          ),
        );

        uiSchedulerChannelCalls.clear();
        await RA_AlarmService.simulateAlarmCallback(routineId);

        final state = await db.getRoutineState(routineId);
        expect(state!.IsRinging, isFalse);
        expect(state.MutedAt, isNotNull);
        expect(state.TimesRingToday, equals(2));
        expect(state.NextTriggerTime, isNotNull);
        expect(state.NextTriggerTime!.isAfter(now), isTrue);

        // Silent muted fire reschedules Dart callback only, never native UI wake.
        expect(
          uiSchedulerChannelCalls.where((c) => c.method == 'schedule'),
          isEmpty,
        );
        expect(
          uiSchedulerChannelCalls.where((c) => c.method == 'cancel'),
          isNotEmpty,
        );

        final logs = await db.getAllLogEntries();
        expect(logs.length, equals(1));
        expect(
          logs.first.LogActionTypeCode,
          LogActionTypeCodeEnum.Dismiss.index,
        );
        expect(logs.first.WasMuted, isTrue);

        await db.close();
        await tempDir.delete(recursive: true);
      },
    );

    test(
      'muteRoutine cancels native alarm UI schedule without scheduling a wake',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_mute_ui_');
        final dbPath = p.join(tempDir.path, 'test.db');
        SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

        final db = RA_Database.openForIsolate(dbPath);
        final now = DateTime.now();
        final next = now.add(const Duration(hours: 2));
        final routineId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Mute Native Cancel'),
            IntervalSeconds: const Value(7200),
            SnoozeSeconds: const Value(300),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            IsActive: const Value(true),
          ),
        );
        await db.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            NextTriggerTime: Value(next),
          ),
        );
        final routine = await db.getRoutineById(routineId);

        uiSchedulerChannelCalls.clear();
        await RA_AlarmService.muteRoutine(
          routineId: routineId,
          db: db,
          routine: routine,
          dbPath: dbPath,
        );

        final cancelCalls = uiSchedulerChannelCalls
            .where((c) => c.method == 'cancel')
            .toList();
        final scheduleCalls = uiSchedulerChannelCalls
            .where((c) => c.method == 'schedule')
            .toList();
        expect(cancelCalls, isNotEmpty);
        final cancelArgs = cancelCalls.last.arguments as Map<Object?, Object?>;
        expect(cancelArgs['routineId'], equals(routineId));
        expect(scheduleCalls, isEmpty);

        // Muting from a paused state resumes internally then cancels native UI.
        await RA_AlarmService.pauseRoutine(
          routineId: routineId,
          db: db,
          routine: routine,
          dbPath: dbPath,
        );
        uiSchedulerChannelCalls.clear();

        await RA_AlarmService.muteRoutine(
          routineId: routineId,
          db: db,
          routine: await db.getRoutineById(routineId),
          dbPath: dbPath,
        );

        final routineCalls = uiSchedulerChannelCalls.where((c) {
          if (c.method != 'schedule' && c.method != 'cancel') return false;
          final args = c.arguments as Map<Object?, Object?>?;
          return args?['routineId'] == routineId;
        }).toList();
        expect(routineCalls, isNotEmpty);
        expect(routineCalls.last.method, equals('cancel'));

        // Muting a currently ringing routine stops native ringing, clears
        // IsRinging, sets MutedAt, and ends with native UI cancelled.
        await db.updateRoutineState(
          routineId,
          const RoutineStatesCompanion(
            IsRinging: Value(true),
            MutedAt: Value(null),
          ),
        );
        uiSchedulerChannelCalls.clear();
        await RA_AlarmService.muteRoutine(
          routineId: routineId,
          db: db,
          routine: await db.getRoutineById(routineId),
          dbPath: dbPath,
        );
        final mutedAfterRing = await db.getRoutineState(routineId);
        expect(mutedAfterRing!.IsRinging, isFalse);
        expect(mutedAfterRing.MutedAt, isNotNull);
        expect(
          uiSchedulerChannelCalls.any((c) => c.method == 'stopRinging'),
          isTrue,
        );
        final ringMuteScheduleCalls = uiSchedulerChannelCalls.where((c) {
          if (c.method != 'schedule' && c.method != 'cancel') return false;
          final args = c.arguments as Map<Object?, Object?>?;
          return args?['routineId'] == routineId;
        }).toList();
        expect(ringMuteScheduleCalls, isNotEmpty);
        expect(ringMuteScheduleCalls.last.method, equals('cancel'));

        await db.close();
        await tempDir.delete(recursive: true);
      },
    );

    test(
      'scheduleNext skips native alarm UI and cancels it while MutedAt != null',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_sched_mute_');
        final dbPath = p.join(tempDir.path, 'test.db');
        SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

        final db = RA_Database.openForIsolate(dbPath);
        final now = DateTime.now();
        final trigger = now.add(const Duration(hours: 1));
        final routineId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Muted Schedule'),
            IntervalSeconds: const Value(3600),
            SnoozeSeconds: const Value(300),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            IsActive: const Value(true),
          ),
        );
        await db.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            NextTriggerTime: Value(trigger),
            MutedAt: Value(now),
          ),
        );
        final routine = await db.getRoutineById(routineId);
        final mutedState = (await db.getRoutineState(routineId))!;

        // 1. Passing muted state directly skips _scheduleAlarmUi and calls cancel.
        alarmChannelCalls.clear();
        uiSchedulerChannelCalls.clear();
        await RA_AlarmService.scheduleNext(
          routineId: routineId,
          triggerTime: trigger,
          dbPath: dbPath,
          routineName: routine.Name,
          routine: routine,
          state: mutedState,
          refreshWidget: false,
        );

        expect(
          alarmChannelCalls.any((c) => c.method == 'Alarm.oneShotAt'),
          isTrue,
        );
        expect(
          uiSchedulerChannelCalls.where((c) => c.method == 'schedule'),
          isEmpty,
        );
        final directCancels = uiSchedulerChannelCalls
            .where((c) => c.method == 'cancel')
            .toList();
        expect(directCancels.length, equals(1));
        expect(
          (directCancels.single.arguments as Map<Object?, Object?>)['routineId'],
          equals(routineId),
        );

        // 2. Omitting state causes scheduleNext to resolve MutedAt from SQLite.
        alarmChannelCalls.clear();
        uiSchedulerChannelCalls.clear();
        await RA_AlarmService.scheduleNext(
          routineId: routineId,
          triggerTime: trigger,
          dbPath: dbPath,
          refreshWidget: false,
        );

        expect(
          alarmChannelCalls.any((c) => c.method == 'Alarm.oneShotAt'),
          isTrue,
        );
        expect(
          uiSchedulerChannelCalls.where((c) => c.method == 'schedule'),
          isEmpty,
        );
        expect(
          uiSchedulerChannelCalls.where((c) => c.method == 'cancel').length,
          equals(1),
        );

        // 3. Contrast: unmuted state DOES invoke native _scheduleAlarmUi.
        uiSchedulerChannelCalls.clear();
        final unmutedState = mutedState.copyWith(MutedAt: const Value(null));
        await RA_AlarmService.scheduleNext(
          routineId: routineId,
          triggerTime: trigger,
          dbPath: dbPath,
          routineName: routine.Name,
          routine: routine,
          state: unmutedState,
          refreshWidget: false,
        );

        final unmutedSchedules = uiSchedulerChannelCalls
            .where((c) => c.method == 'schedule')
            .toList();
        expect(unmutedSchedules.length, equals(1));
        expect(
          (unmutedSchedules.single.arguments
              as Map<Object?, Object?>)['routineId'],
          equals(routineId),
        );

        await db.close();
        await tempDir.delete(recursive: true);
      },
    );

    test(
      'unmuteRoutine re-arms native alarm UI schedule for active routine and skips inactive ones',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_unmute_ui_');
        final dbPath = p.join(tempDir.path, 'test.db');
        SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

        final db = RA_Database.openForIsolate(dbPath);
        final now = DateTime.now();
        final trigger = DateTime.fromMillisecondsSinceEpoch(
          (now.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000) *
              1000,
        );
        final routineId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Unmute Re-arm'),
            IntervalSeconds: const Value(7200),
            SnoozeSeconds: const Value(300),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            Vibrate: const Value(true),
            Volume: const Value(80),
            FadeIn: const Value(true),
            IsActive: const Value(true),
          ),
        );
        await db.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            NextTriggerTime: Value(trigger),
            MutedAt: Value(now.subtract(const Duration(minutes: 5))),
          ),
        );

        uiSchedulerChannelCalls.clear();
        await RA_AlarmService.unmuteRoutine(routineId: routineId, db: db);

        final after = await db.getRoutineState(routineId);
        expect(after!.MutedAt, isNull);
        expect(
          after.NextTriggerTime!.millisecondsSinceEpoch,
          equals(trigger.millisecondsSinceEpoch),
        );

        final scheduleCalls = uiSchedulerChannelCalls
            .where((c) => c.method == 'schedule')
            .toList();
        expect(scheduleCalls.length, equals(1));
        final args = scheduleCalls.single.arguments as Map<Object?, Object?>;
        expect(args['routineId'], equals(routineId));
        expect(args['triggerAtMillis'], equals(trigger.millisecondsSinceEpoch));
        expect(args['volume'], closeTo(0.8, 0.001));
        expect(args['fadeInMs'], greaterThan(0));
        expect(args['vibrate'], isTrue);

        // Inactive routine should clear MutedAt without arming native UI.
        final inactiveId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Inactive Muted'),
            IntervalSeconds: const Value(7200),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            IsActive: const Value(false),
          ),
        );
        await db.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(inactiveId),
            NextTriggerTime: Value(trigger),
            MutedAt: Value(now),
          ),
        );

        uiSchedulerChannelCalls.clear();
        await RA_AlarmService.unmuteRoutine(routineId: inactiveId, db: db);
        expect((await db.getRoutineState(inactiveId))!.MutedAt, isNull);
        expect(
          uiSchedulerChannelCalls.where((c) => c.method == 'schedule'),
          isEmpty,
        );

        await db.close();
        await tempDir.delete(recursive: true);
      },
    );

    test(
      'scheduleNext and reconcileAlarmsOnStartup never invoke requestIgnoreBatteryOptimizations',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_no_batt_');
        final dbPath = p.join(tempDir.path, 'test.db');
        SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

        final db = RA_Database.openForIsolate(dbPath);
        final now = DateTime.now();
        final trigger = now.add(const Duration(hours: 3));
        final routineId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('No Battery Prompt'),
            IntervalSeconds: const Value(10800),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            IsActive: const Value(true),
          ),
        );
        await db.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            NextTriggerTime: Value(trigger),
          ),
        );
        final routine = await db.getRoutineById(routineId);
        final state = (await db.getRoutineState(routineId))!;

        // Simulate an OEM device where battery exemption is NOT granted so any
        // legacy auto-prompt inside scheduleNext would fire requestIgnore*.
        mockIgnoringBatteryOptimizations = false;
        uiSchedulerChannelCalls.clear();
        await RA_AlarmService.scheduleNext(
          routineId: routineId,
          triggerTime: trigger,
          dbPath: dbPath,
          routineName: routine.Name,
          routine: routine,
          state: state,
          refreshWidget: false,
        );
        await RA_AlarmService.reconcileAlarmsOnStartup(db: db, dbPath: dbPath);

        const forbiddenBatteryMethods = {
          'requestIgnoreBatteryOptimizations',
          'ensureIgnoringBatteryOptimizations',
          'isIgnoringBatteryOptimizations',
        };
        final batteryCalls = uiSchedulerChannelCalls
            .where((c) => forbiddenBatteryMethods.contains(c.method))
            .toList();
        expect(batteryCalls, isEmpty);

        await db.close();
        await tempDir.delete(recursive: true);
      },
    );

    test(
      'syncAlarmUiSchedules cancels muted routines and schedules unmuted routines',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_sync_ui_');
        final dbPath = p.join(tempDir.path, 'test.db');
        SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

        final db = RA_Database.openForIsolate(dbPath);
        final now = DateTime.now();
        final trigger = now.add(const Duration(hours: 1));

        final activeId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Active Unmuted'),
            IntervalSeconds: const Value(3600),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            IsActive: const Value(true),
          ),
        );
        await db.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(activeId),
            NextTriggerTime: Value(trigger),
          ),
        );

        final mutedId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Active Muted'),
            IntervalSeconds: const Value(3600),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            IsActive: const Value(true),
          ),
        );
        await db.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(mutedId),
            NextTriggerTime: Value(trigger),
            MutedAt: Value(now),
          ),
        );

        uiSchedulerChannelCalls.clear();
        await RA_AlarmService.syncAlarmUiSchedules(db);

        final scheduledIds = uiSchedulerChannelCalls
            .where((c) => c.method == 'schedule')
            .map((c) => (c.arguments as Map<Object?, Object?>)['routineId'])
            .toList();
        final cancelledIds = uiSchedulerChannelCalls
            .where((c) => c.method == 'cancel')
            .map((c) => (c.arguments as Map<Object?, Object?>)['routineId'])
            .toList();

        expect(scheduledIds, equals([activeId]));
        expect(cancelledIds, equals([mutedId]));

        await db.close();
        await tempDir.delete(recursive: true);
      },
    );

    test(
      'stale ExtraMaxTimesToday does not resurrect on day rollover in nextTriggerForAction or handleTransition',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_extra_roll_');
        final dbPath = p.join(tempDir.path, 'test.db');
        SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

        final db = RA_Database.openForIsolate(dbPath);
        final now = DateTime.now();
        final todayPeriod = RA_DailyRingLimit.periodStart(now, 0);
        final yesterdayPeriod = DateTime(
          todayPeriod.year,
          todayPeriod.month,
          todayPeriod.day - 1,
        );
        final tomorrowDayStart = RA_DailyRingLimit.nextCalendarDayStart(now, 0);

        final routineId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Extra Rollover'),
            IntervalSeconds: const Value(3600),
            SnoozeSeconds: const Value(300),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            MaxTimesPerDayEnabled: const Value(true),
            MaxTimesPerDay: const Value(1),
            DayStartSeconds: const Value(0),
            IsActive: const Value(true),
          ),
        );
        await db.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            NextTriggerTime: Value(now),
            InitialRingTime: Value(now),
            IsRinging: const Value(true),
            TimesRingToday: const Value(4),
            ExtraMaxTimesToday: const Value(5),
            TimesRingDay: Value(yesterdayPeriod),
          ),
        );
        final routine = await db.getRoutineById(routineId);
        final state = (await db.getRoutineState(routineId))!;

        // Preview math: on a new day, count resets to 0 -> +1 = 1 == MaxTimesPerDay(1),
        // and yesterday's ExtraMaxTimesToday=5 must NOT apply -> parks at tomorrow day-start.
        final previewNext = RA_AlarmService.nextTriggerForAction(
          action: RA_AlarmActionTypeCodeEnum.Dismiss,
          routine: routine,
          state: state,
          now: now,
        );
        expect(previewNext, equals(tomorrowDayStart));

        await RA_AlarmService.handleTransition(
          action: RA_AlarmActionTypeCodeEnum.Dismiss,
          routineId: routineId,
          db: db,
          routine: routine,
          state: state,
        );

        final after = await db.getRoutineState(routineId);
        expect(after!.TimesRingToday, equals(1));
        expect(after.ExtraMaxTimesToday, equals(0));
        expect(after.NextTriggerTime, equals(tomorrowDayStart));

        await db.close();
        await tempDir.delete(recursive: true);
      },
    );

    test(
      'resetTodayCounter does not arm a paused routine and recoverRoutine returns false on missing ID',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_paused_rst_');
        final dbPath = p.join(tempDir.path, 'test.db');
        SharedPreferences.setMockInitialValues({'ra_db_path': dbPath});

        final db = RA_Database.openForIsolate(dbPath);
        const dayStartSeconds = 6 * 3600;
        final now = DateTime.now();
        final dayStart = RA_DailyRingLimit.nextPeriodStartAfter(
          now,
          dayStartSeconds,
        );
        final routineId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Paused Reset'),
            IntervalSeconds: const Value(3600),
            SnoozeSeconds: const Value(300),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            MaxTimesPerDayEnabled: const Value(true),
            MaxTimesPerDay: const Value(2),
            DayStartSeconds: const Value(dayStartSeconds),
            IsActive: const Value(true),
          ),
        );
        await db.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            NextTriggerTime: Value(dayStart),
            PausedAt: Value(now.subtract(const Duration(minutes: 10))),
            TimesRingToday: const Value(2),
            TimesRingDay: Value(
              RA_DailyRingLimit.periodStart(now, dayStartSeconds),
            ),
          ),
        );
        final staleActiveRoutine = await db.getRoutineById(routineId);

        alarmChannelCalls.clear();
        uiSchedulerChannelCalls.clear();
        await RA_AlarmService.resetTodayCounter(
          routineId: routineId,
          db: db,
          routine: staleActiveRoutine,
          dbPath: dbPath,
        );

        expect(
          alarmChannelCalls.where((c) => c.method == 'Alarm.oneShotAt'),
          isEmpty,
        );
        expect(
          uiSchedulerChannelCalls.where((c) => c.method == 'schedule'),
          isEmpty,
        );

        // recoverRoutine returns false rather than throwing StateError for unknown ID.
        expect(
          await RA_AlarmService.recoverRoutine(
            routineId: 999999,
            db: db,
            dbPath: dbPath,
          ),
          isFalse,
        );

        await db.close();
        await tempDir.delete(recursive: true);
      },
    );

    test(
      'cancelNotification still stops native ringing and clears prefs if plugin cancel throws, and audio start/stop race is safe',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(RA_NotificationService.ringingPrefKey, true);
        await prefs.setInt(RA_NotificationService.alarmWakeAtPrefKey, 12345);

        const notifChannel = MethodChannel(
          'dexterous.com/flutter/local_notifications',
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(notifChannel, (MethodCall call) async {
              if (call.method == 'cancel') {
                throw MissingPluginException('simulated missing plugin');
              }
              return true;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(notifChannel, (MethodCall call) async {
                notifChannelCalls.add(call);
                if (call.method == 'canUseFullScreenIntent') return true;
                return true;
              });
        });

        uiSchedulerChannelCalls.clear();
        await RA_NotificationService.cancelNotification(77);

        expect(
          uiSchedulerChannelCalls.any((c) => c.method == 'stopRinging'),
          isTrue,
        );
        expect(prefs.getBool(RA_NotificationService.ringingPrefKey), isFalse);
        expect(prefs.getInt(RA_NotificationService.alarmWakeAtPrefKey), isNull);

        await Future.wait([
          RA_AudioService.startAlarm(volume: 80, fadeIn: true),
          RA_AudioService.stopAlarm(),
        ]);
      },
    );
  });
}
