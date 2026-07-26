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
}

class FakeRoutineStatesCompanion extends Fake
    implements RoutineStatesCompanion {}

class FakeLogEntriesCompanion extends Fake implements LogEntriesCompanion {}

void main() {
  final alarmChannelCalls = <MethodCall>[];
  final notifChannelCalls = <MethodCall>[];

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
      'com.example.rolling_alarm/alarm_ui_scheduler',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(uiSchedulerChannel, (MethodCall methodCall) async {
          if (methodCall.method == 'isIgnoringBatteryOptimizations') {
            return true;
          }
          if (methodCall.method == 'requestIgnoreBatteryOptimizations') {
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
  });

  group('RA_AlarmService Plugin Boundary Tests', () {
    late MockDatabase mockDb;

    setUp(() {
      mockDb = MockDatabase();
      SharedPreferences.setMockInitialValues({});
      alarmChannelCalls.clear();
      notifChannelCalls.clear();
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
          DriftCompensationTypeCode:
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
          ShowPreview: true,
          Vibrate: true,
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
          TimesRingDay: null,
          LastDismissedAt: null,
          CreatedAt: now,
          ModifiedAt: null,
          Deleted: false,
        );

        when(() => mockDb.getRoutineState(routine.Id)).thenAnswer((_) async => state);
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
          DriftCompensationTypeCode:
              DriftCompensationTypeCodeEnum.InitialRing.index,
          ShowPreview: true,
          Vibrate: true,
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
          TimesRingDay: null, // already snoozed once
          LastDismissedAt: null,
          CreatedAt: now,
          ModifiedAt: null,
          Deleted: false,
        );

        when(() => mockDb.getRoutineState(routine.Id)).thenAnswer((_) async => state);
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
          DriftCompensationTypeCode:
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
          ShowPreview: true,
          Vibrate: true,
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
      'scheduleNext passes alarmClock, exact, wakeup, allowWhileIdle, and rescheduleOnReboot to oneShotAt',
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
        expect(args[1], isTrue); // alarmClock -> setAlarmClock
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
        DriftCompensationTypeCode:
            DriftCompensationTypeCodeEnum.InitialRing.index,
        ShowPreview: true,
        Vibrate: true,
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
          TimesRingDay: null,
        LastDismissedAt: now.subtract(const Duration(hours: 4)),
        CreatedAt: now,
        ModifiedAt: null,
        Deleted: false,
      );

      when(() => mockDb.getRoutineState(routine.Id)).thenAnswer((_) async => state);
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

    test('handleTransition Skip with countSkipTowardsDaily increments TimesRingToday',
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
        DriftCompensationTypeCode:
            DriftCompensationTypeCodeEnum.ActualDismissal.index,
        ShowPreview: true,
        Vibrate: true,
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
        TimesRingDay: RA_DailyRingLimit.periodStart(now, 0),
        LastDismissedAt: null,
        CreatedAt: now,
        ModifiedAt: null,
        Deleted: false,
      );

      when(() => mockDb.getRoutineState(routine.Id))
          .thenAnswer((_) async => state);
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
    });

    test(
      'RA_NotificationService showAlarmNotification posts full-screen intent alarm',
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
        expect(showCalls, isNotEmpty);
        final args = showCalls.last.arguments as Map<dynamic, dynamic>;
        expect(args['id'], 1);
        expect(args['title'], 'Morning Alarm');
        expect(
          args.keys.map((k) => k.toString()).toList(),
          contains('platformSpecifics'),
          reason: 'show arg keys=${args.keys.toList()}',
        );
        final platform = args['platformSpecifics'] as Map<dynamic, dynamic>?;
        expect(platform, isNotNull);
        expect(platform!['fullScreenIntent'], isTrue);
        expect(platform['category'], 'alarm');
        expect(platform['ongoing'], isTrue);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(RA_NotificationService.ringingPrefKey), isTrue);

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
        final tempDir =
            await Directory.systemTemp.createTemp('ra_cross_conn_');
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
        final tempDir =
            await Directory.systemTemp.createTemp('ra_reconcile_ring_');
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
  });
}
