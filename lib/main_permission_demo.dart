/// Play Console permission demo entry point. Never shipped: release builds use
/// `lib/main.dart`. Built and driven by `scripts/record_permission_demos.sh`.
///
/// Starts exactly like `lib/main.dart` (alarm service, notifications, UI port
/// and startup reconcile), except that it first replaces all data with two
/// routines, one of which is due a few seconds after launch. The reconcile
/// arms that routine through the normal scheduling path, so the recorded
/// alarm is a real exact alarm that wakes the device through the full screen
/// intent and rings in the foreground service.
///
/// ```
/// adb shell am start -n com.casellaweb.rolling_alarm/.MainActivity \
///   --es route "/demo?in=20"
/// ```
///
/// `in` is the number of seconds from launch until the alarm fires (default
/// 20). Once the alarm is armed and the dashboard is drawn,
/// `RA_DEMO_READY <epoch millis of the alarm>` is printed to logcat.
library;

import 'dart:async';
import 'dart:ui';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/app_theme_mode.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';
import 'package:rolling_alarm/enums/log_action_type_code.dart';
import 'package:rolling_alarm/main.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/daily_ring_limit.dart';
import 'package:rolling_alarm/services/notification.dart';
import 'package:rolling_alarm/services/settings.dart';
import 'package:rolling_alarm/styles.dart';

const int _defaultLeadSeconds = 20;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final uri = Uri.parse(PlatformDispatcher.instance.defaultRouteName);
  final leadSeconds =
      int.tryParse(uri.queryParameters['in'] ?? '') ?? _defaultLeadSeconds;

  final dbPath = await RA_Database.resolveDatabasePath();
  await RA_AlarmService.persistDatabasePath(dbPath);
  await RA_SettingsService.setThemeMode(AppThemeModeEnum.Dark);
  final database = RA_Database();
  RA_NotificationService.bindUiDatabase(database);

  RA_AlarmService.registerUiPort(
    (_) => database.notifyUpdates({
      TableUpdate.onTable(database.routines),
      TableUpdate.onTable(database.routineStates),
      TableUpdate.onTable(database.logEntries),
    }),
  );

  await RA_AlarmService.init();
  await RA_NotificationService.init();
  final fireAt = await _seedDemoRoutines(database, leadSeconds);
  await RA_AlarmService.reconcileAlarmsOnStartup(db: database, dbPath: dbPath);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  RA_ColourStyles.apply(AppThemeModeEnum.Dark);
  SystemChrome.setSystemUIOverlayStyle(RA_AppTheme.systemUiOverlayStyle());

  runApp(
    ProviderScope(
      overrides: [RA_DatabaseProvider.overrideWithValue(database)],
      child: RollingAlarmApp(dbPath: dbPath),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // RA_AlarmRingPresenter arms the native setAlarmClock after the first
    // frame; give it a moment before reporting ready.
    await Future<void>.delayed(const Duration(seconds: 1));
    debugPrint('RA_DEMO_READY ${fireAt.millisecondsSinceEpoch}');
  });
}

/// Replaces all data with a "Medication" routine due in [leadSeconds] and a
/// "Hydrate" routine due much later, and returns the Medication fire time.
Future<DateTime> _seedDemoRoutines(RA_Database db, int leadSeconds) async {
  final now = DateTime.fromMillisecondsSinceEpoch(
    DateTime.now().millisecondsSinceEpoch ~/ 1000 * 1000,
  );
  const dayStart = 6 * 3600;
  final today = RA_DailyRingLimit.periodStart(now, dayStart);
  final fireAt = now.add(Duration(seconds: leadSeconds));

  await db.transaction(() async {
    await db.delete(db.logEntries).go();
    await db.delete(db.routineStates).go();
    await db.delete(db.routines).go();

    final medicationCreated = now.subtract(const Duration(days: 5));
    final medication = await db.insertRoutine(
      RoutinesCompanion.insert(
        Name: 'Medication',
        IntervalSeconds: 8 * 3600,
        SnoozeSeconds: const Value(10 * 60),
        DriftCompensationTypeCode:
            DriftCompensationTypeCodeEnum.InitialRing.index,
        DayStartSeconds: const Value(dayStart),
        CreatedAt: Value(medicationCreated),
      ),
    );
    await db.insertRoutineState(
      RoutineStatesCompanion.insert(
        RoutineId: medication,
        NextTriggerTime: Value(fireAt),
        TimesRingToday: const Value(1),
        TimesRingDay: Value(today),
      ),
    );

    final hydrateCreated = now.subtract(const Duration(days: 3));
    final hydrate = await db.insertRoutine(
      RoutinesCompanion.insert(
        Name: 'Hydrate',
        IntervalSeconds: 3600,
        SnoozeSeconds: const Value(5 * 60),
        DriftCompensationTypeCode:
            DriftCompensationTypeCodeEnum.ActualDismissal.index,
        DayStartSeconds: const Value(dayStart),
        CreatedAt: Value(hydrateCreated),
      ),
    );
    await db.insertRoutineState(
      RoutineStatesCompanion.insert(
        RoutineId: hydrate,
        NextTriggerTime: Value(now.add(const Duration(minutes: 42))),
        TimesRingToday: const Value(2),
        TimesRingDay: Value(today),
      ),
    );

    for (final (routineId, created) in [
      (medication, medicationCreated),
      (hydrate, hydrateCreated),
    ]) {
      await db.insertLogEntry(
        LogEntriesCompanion.insert(
          RoutineId: routineId,
          Timestamp: created,
          LogActionTypeCode: LogActionTypeCodeEnum.Create.index,
        ),
      );
    }
  });

  return fireAt;
}
