import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/alarm_action_type_code.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';
import 'package:rolling_alarm/enums/log_action_type_code.dart';
import 'package:rolling_alarm/services/alarm_calculator.dart';
import 'package:rolling_alarm/services/audio.dart';
import 'package:rolling_alarm/services/daily_ring_limit.dart';
import 'package:rolling_alarm/services/notification.dart';
import 'package:rolling_alarm/services/widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages alarm scheduling, the background isolate callback, and
/// snooze/dismiss/skip/auto-snooze state transitions.
class RA_AlarmService {
  RA_AlarmService._();

  static const String _dbPathKey = 'ra_db_path';
  static const String _portName = 'ra_alarm_port';
  static const String _uiSchedulerChannel =
      'com.example.rolling_alarm/alarm_ui_scheduler';
  static const int _alarmIdBase = 1000;
  static const int _watchdogIdBase = 5000;

  /// UI-isolate receive port for background pings. Kept so re-register
  /// (hot restart) can close the previous port instead of leaking it.
  static ReceivePort? _uiReceivePort;
  static StreamSubscription<dynamic>? _uiPortSubscription;

  /// Initialises the alarm manager plugin. Call once from main().
  static Future<void> init() async {
    try {
      await AndroidAlarmManager.initialize();
    } catch (_) {
      // Ignore alarm manager init errors in test environments
    }
  }

  /// Persists [dbPath] for background isolates before any alarm can fire.
  /// Call from [main] immediately after [RA_Database.resolveDatabasePath]
  /// so a pending OS one-shot cannot open Drift with a missing path.
  /// Never throws into [main].
  static Future<void> persistDatabasePath(String dbPath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dbPathKey, dbPath);
    } catch (_) {
      // Prefs failures must not block app start; reconcile retries later.
    }
  }

  /// Re-arms AlarmManager timers from Drift after cold start, reboot, or
  /// force-stop. Native [RebootBroadcastReceiver] already restores
  /// `rescheduleOnReboot` one-shots when possible; this path covers cases
  /// where OS timers were cleared but [NextTriggerTime] / [IsRinging] still
  /// exist in the database. Never throws into [main].
  static Future<void> reconcileAlarmsOnStartup({
    required RA_Database db,
    required String dbPath,
  }) async {
    try {
      await persistDatabasePath(dbPath);

      final prefs = await SharedPreferences.getInstance();
      final routines = await db.getActiveRoutines();
      for (final routine in routines) {
        try {
          final state = await db.getRoutineState(routine.Id);
          if (state == null) continue;

          await prefs.setInt(
            'ra_alarm_routine_id_${_alarmIdBase + routine.Id}',
            routine.Id,
          );

            if (state.IsRinging) {
            await RA_NotificationService.showAlarmNotification(
              routineId: routine.Id,
              routineName: routine.Name,
              vibrate: routine.Vibrate,
            );
            // Replace any reboot-restored watchdog with a fresh window from now.
            await _cancelWatchdog(routine.Id);
            await _scheduleWatchdog(
              routineId: routine.Id,
              snoozeSeconds: routine.SnoozeSeconds,
            );
            continue;
          }

          final next = state.NextTriggerTime;
          if (next == null) continue;

          await scheduleNext(
            routineId: routine.Id,
            triggerTime: next,
            dbPath: dbPath,
            routineName: routine.Name,
          );
        } catch (_) {
          // One bad routine must not block re-arming the rest.
        }
      }
    } catch (_) {
      // Startup must never crash on reconcile failure.
    }
  }

  /// Schedules the next alarm for [routineId] at [triggerTime].
  ///
  /// Always runs the aggressive battery-optimization check first so create /
  /// toggle / reschedule paths cannot silently stay under OEM Doze limits.
  static Future<void> scheduleNext({
    required int routineId,
    required DateTime triggerTime,
    required String dbPath,
    String? routineName,
  }) async {
    try {
      // Force Unrestricted battery mode before any AlarmManager arming.
      // scheduleNext is the single create / toggle / reschedule entry point.
      await ensureBatteryOptimizationExempt();

      // Persist the DB path so the background isolate can find it
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dbPathKey, dbPath);
      await prefs.setInt(
        'ra_alarm_routine_id_${_alarmIdBase + routineId}',
        routineId,
      );

      // Missed triggers (edit/import/reconcile after the planned time) must
      // still fire soon instead of silently dropping the schedule.
      // Use absolute oneShotAt + setAlarmClock so Samsung / Doze cannot defer
      // the fire the way setExactAndAllowWhileIdle often does.
      final now = DateTime.now();
      final fireAt = triggerTime.isAfter(now)
          ? triggerTime
          : now.add(const Duration(seconds: 1));

      await AndroidAlarmManager.oneShotAt(
        fireAt,
        _alarmIdBase + routineId,
        _alarmCallback,
        alarmClock: true,
        exact: true,
        wakeup: true,
        allowWhileIdle: true,
        rescheduleOnReboot: true,
      );

      // Parallel setAlarmClock -> AlarmReceiver -> AlarmRingingService FSI
      // (works even when the Flutter UI process was killed). Best-effort.
      await _scheduleAlarmUi(fireAt: fireAt, routineId: routineId);

      await RA_WidgetService.updateWidget(
        routineName: routineName ?? 'Rolling Alarm',
        nextTriggerTime: triggerTime,
        routineId: routineId,
      );
    } catch (_) {
      // Platform channel / permission failures must not crash callers.
    }
  }

  /// Cancels any pending alarm for the given routine.
  static Future<void> cancel(int routineId) async {
    try {
      await AndroidAlarmManager.cancel(_alarmIdBase + routineId);
      await AndroidAlarmManager.cancel(_watchdogIdBase + routineId);
      await _cancelAlarmUi(routineId);
    } catch (_) {
      // Ignore alarm cancel errors in test environments
    }
  }

  /// Schedules a native setAlarmClock that fires [AlarmReceiver] / FGS + FSI.
  static Future<void> _scheduleAlarmUi({
    required DateTime fireAt,
    required int routineId,
  }) async {
    try {
      const channel = MethodChannel(_uiSchedulerChannel);
      await channel.invokeMethod<void>('schedule', <String, dynamic>{
        'triggerAtMillis': fireAt.millisecondsSinceEpoch,
        'routineId': routineId,
      });
    } catch (_) {
      // Channel missing in headless / background isolates; FSI still covers wake.
    }
  }

  static Future<void> _cancelAlarmUi(int routineId) async {
    try {
      const channel = MethodChannel(_uiSchedulerChannel);
      await channel.invokeMethod<void>('cancel', <String, dynamic>{
        'routineId': routineId,
      });
    } catch (_) {}
  }

  /// Stops the native [AlarmRingingService] foreground wake for [routineId].
  static Future<void> stopNativeRinging(int routineId) async {
    try {
      const channel = MethodChannel(_uiSchedulerChannel);
      await channel.invokeMethod<void>('stopRinging', <String, dynamic>{
        'routineId': routineId,
      });
    } catch (_) {}
  }

  /// Whether the OS has exempted this app from battery optimizations.
  ///
  /// Without exemption, Samsung / Xiaomi routinely kill alarm receivers and
  /// background Drift isolates, so full-screen wake becomes unreliable.
  static Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      const channel = MethodChannel(_uiSchedulerChannel);
      final result = await channel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Prompts the user via [ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS].
  ///
  /// Returns true if already exempt or the system dialog / settings page was
  /// launched successfully.
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      const channel = MethodChannel(_uiSchedulerChannel);
      final result = await channel.invokeMethod<bool>(
        'requestIgnoreBatteryOptimizations',
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Ensures battery exemption; prompts when not granted.
  ///
  /// Called from [scheduleNext] on every create / toggle / reschedule, and
  /// once at app startup, so the user cannot bypass Unrestricted mode.
  static Future<void> ensureBatteryOptimizationExempt() async {
    try {
      const channel = MethodChannel(_uiSchedulerChannel);
      // Prefer the combined native check+prompt so the dialog fires immediately.
      final ensured = await channel.invokeMethod<bool>(
        'ensureIgnoringBatteryOptimizations',
      );
      if (ensured == true) return;
      // Older plugin builds may lack the combined method; fall back.
      if (await isIgnoringBatteryOptimizations()) return;
      await requestIgnoreBatteryOptimizations();
    } catch (_) {
      try {
        if (await isIgnoringBatteryOptimizations()) return;
        await requestIgnoreBatteryOptimizations();
      } catch (_) {}
    }
  }

  /// Re-arms native AlarmReceiver setAlarmClock timers from Drift. Call once the
  /// UI engine is up (reconcile in [main] runs too early for this channel).
  static Future<void> syncAlarmUiSchedules(RA_Database db) async {
    try {
      final routines = await db.getActiveRoutines();
      for (final routine in routines) {
        try {
          final state = await db.getRoutineState(routine.Id);
          if (state == null || state.IsRinging) continue;
          final next = state.NextTriggerTime;
          if (next == null) continue;
          final now = DateTime.now();
          final fireAt = next.isAfter(now)
              ? next
              : now.add(const Duration(seconds: 1));
          await _scheduleAlarmUi(fireAt: fireAt, routineId: routine.Id);
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Schedules the auto-snooze watchdog alarm.
  static Future<void> _scheduleWatchdog({
    required int routineId,
    required int snoozeSeconds,
  }) async {
    try {
      await AndroidAlarmManager.oneShotAt(
        DateTime.now().add(Duration(seconds: snoozeSeconds)),
        _watchdogIdBase + routineId,
        _watchdogCallback,
        alarmClock: true,
        exact: true,
        wakeup: true,
        allowWhileIdle: true,
        rescheduleOnReboot: true,
      );
    } catch (_) {
      // Ignore watchdog scheduling errors in test environments
    }
  }

  /// Cancels the auto-snooze watchdog alarm for the given routine.
  static Future<void> _cancelWatchdog(int routineId) async {
    try {
      await AndroidAlarmManager.cancel(_watchdogIdBase + routineId);
    } catch (_) {
      // Ignore watchdog cancel errors in test environments
    }
  }

  // --------------------------------------------------------------------- //
  // Background isolate callbacks
  // --------------------------------------------------------------------- //

  @pragma('vm:entry-point')
  static Future<void> _alarmCallback(int alarmId) async {
    RA_Database? db;
    try {
      final prefs = await SharedPreferences.getInstance();
      final dbPath = prefs.getString(_dbPathKey);
      if (dbPath == null) return;

      final routineId =
          prefs.getInt('ra_alarm_routine_id_$alarmId') ??
          (alarmId - _alarmIdBase);

      db = RA_Database.openForIsolate(dbPath);

      // Background isolates must re-init plugins that talk to platform channels.
      await RA_NotificationService.init();

      final routine = await db.getRoutineById(routineId);
      if (routine.Deleted || !routine.IsActive) {
        await cancel(routineId);
        return;
      }

      // Imported routines may lack a state row; ensure one without racing
      // duplicate inserts against a concurrent UI writer.
      final state = await db.ensureRoutineState(routineId);
      if (state == null) {
        // Soft-deleted or otherwise unavailable; do not revive via blind update.
        return;
      }
      final now = DateTime.now();

      // A re-ring after snooze must preserve InitialRingTime and CurrentSnoozeCount.
      // Only a fresh interval cycle (snooze count at zero) records a new initial ring.
      // CAS requireIsRinging=false so a duplicate OS delivery or a soft-deleted
      // state cannot reset InitialRingTime / snooze count or double-notify.
      final isResumingFromSnooze = state.CurrentSnoozeCount > 0;

      if (!isResumingFromSnooze) {
        final canRing = RA_DailyRingLimit.canRingToday(
          maxTimesPerDay: routine.MaxTimesPerDayEnabled
              ? routine.MaxTimesPerDay
              : 0,
          timesRingToday: state.TimesRingToday,
          timesRingDay: state.TimesRingDay,
          now: now,
          dayStartSeconds: routine.DayStartSeconds,
        );
        if (!canRing) {
          final deferred = RA_DailyRingLimit.nextPeriodStartAfter(
            now,
            routine.DayStartSeconds,
          );
          await db.updateRoutineState(
            routineId,
            RoutineStatesCompanion(
              NextTriggerTime: Value(deferred),
              IsRinging: const Value(false),
            ),
            requireIsRinging: false,
          );
          await scheduleNext(
            routineId: routineId,
            triggerTime: deferred,
            dbPath: dbPath,
            routineName: routine.Name,
          );
          return;
        }
      }

      final period = RA_DailyRingLimit.periodStart(
        now,
        routine.DayStartSeconds,
      );
      final priorCount = RA_DailyRingLimit.countForDay(
        timesRingToday: state.TimesRingToday,
        timesRingDay: state.TimesRingDay,
        now: now,
        dayStartSeconds: routine.DayStartSeconds,
      );

      final int rows;
      if (isResumingFromSnooze) {
        rows = await db.updateRoutineState(
          routineId,
          const RoutineStatesCompanion(IsRinging: Value(true)),
          requireIsRinging: false,
        );
      } else {
        rows = await db.updateRoutineState(
          routineId,
          RoutineStatesCompanion(
            InitialRingTime: Value(now),
            IsRinging: const Value(true),
            CurrentSnoozeCount: const Value(0),
            TimesRingToday: Value(priorCount + 1),
            TimesRingDay: Value(period),
          ),
          requireIsRinging: false,
        );
      }
      if (rows == 0) return;

      // Wake UI / lock-screen paths BEFORE audio. just_audio init can hang or
      // fail on OEM devices; the ring page must still appear on time.
      await RA_NotificationService.showAlarmNotification(
        routineId: routineId,
        routineName: routine.Name,
        vibrate: routine.Vibrate,
      );
      _pingUiIsolate(routineId);

      await _scheduleWatchdog(
        routineId: routineId,
        snoozeSeconds: routine.SnoozeSeconds,
      );

      try {
        await RA_AudioService.startAlarm(
          audioUri: routine.AudioUri,
          vibrate: routine.Vibrate,
        );
      } catch (_) {
        // Ring UI + FSI notification already posted; audio can retry on ring page.
      }

      // Second ping in case the first raced ahead of Drift visibility.
      _pingUiIsolate(routineId);
    } catch (_) {
      // Never let an unhandled exception kill the background isolate mid-ring.
    } finally {
      await db?.close();
    }
  }

  @pragma('vm:entry-point')
  static Future<void> _watchdogCallback(int alarmId) async {
    RA_Database? db;
    try {
      final routineId = alarmId - _watchdogIdBase;
      final prefs = await SharedPreferences.getInstance();
      final dbPath = prefs.getString(_dbPathKey);
      if (dbPath == null) return;

      db = RA_Database.openForIsolate(dbPath);

      final routine = await db.getRoutineById(routineId);
      if (routine.Deleted || !routine.IsActive) {
        await cancel(routineId);
        return;
      }

      final state = await db.getRoutineState(routineId);
      if (state == null || !state.IsRinging) return;

      await handleTransition(
        action: RA_AlarmActionTypeCodeEnum.AutoSnooze,
        routineId: routineId,
        db: db,
        routine: routine,
        state: state,
      );
    } catch (_) {
      // Never let an unhandled exception kill the watchdog isolate.
    } finally {
      await db?.close();
    }
  }

  /// Handles a user or system action (Dismiss, Snooze, Skip, AutoSnooze)
  /// by calculating the next trigger, updating state, logging, and
  /// rescheduling.
  ///
  /// State update and log insert run inside a single Drift transaction.
  /// Dismiss / Snooze / AutoSnooze use a compare-and-swap on [IsRinging] so a
  /// UI action and a watchdog/alarm isolate writing on separate connections
  /// cannot both commit against the same ring (a plain re-read is not enough
  /// across SQLite connections).
  ///
  /// When [action] is [RA_AlarmActionTypeCodeEnum.Skip] and
  /// [countSkipTowardsDaily] is true, increments [TimesRingToday] for an idle
  /// (not yet ringing) skip. Live rings already counted at trigger time.
  static Future<void> handleTransition({
    required RA_AlarmActionTypeCodeEnum action,
    required int routineId,
    required RA_Database db,
    required RoutineModel routine,
    required RoutineStateModel state,
    bool countSkipTowardsDaily = false,
  }) async {
    final now = DateTime.now();
    final compensation =
        DriftCompensationTypeCodeEnum.values[routine.DriftCompensationTypeCode];

    DateTime? nextTrigger;

    // Caller snapshot is advisory; the transaction re-reads for race safety.
    assert(state.RoutineId == routineId);

    await db.transaction(() async {
      // Re-read so same-connection concurrent callers see the latest row.
      final fresh = await db.getRoutineState(routineId);
      if (fresh == null) return;

      // Ringing actions must still see IsRinging=true. Skip may run while idle
      // (home widget / countdown skip) so it does not require a live ring.
      final requiresRinging = action != RA_AlarmActionTypeCodeEnum.Skip;
      if (requiresRinging && !fresh.IsRinging) return;

      final calculated = RA_AlarmCalculator.calculateNextTrigger(
        Action: action,
        Compensation: compensation,
        IntervalSeconds: routine.IntervalSeconds,
        SnoozeSeconds: routine.SnoozeSeconds,
        InitialRingTime: fresh.InitialRingTime ?? now,
        Now: now,
      );

      final isEffectiveDismiss =
          action == RA_AlarmActionTypeCodeEnum.Dismiss ||
          action == RA_AlarmActionTypeCodeEnum.Skip;

      // Idle Skip can optionally count as a "gone off" for today's total.
      // Do not increment while already ringing; triggerAlarm already counted.
      final shouldCountSkip =
          action == RA_AlarmActionTypeCodeEnum.Skip &&
          countSkipTowardsDaily &&
          !fresh.IsRinging;

      var timesRingToday = fresh.TimesRingToday;
      var timesRingDay = fresh.TimesRingDay;
      if (shouldCountSkip) {
        final period = RA_DailyRingLimit.periodStart(
          now,
          routine.DayStartSeconds,
        );
        final priorCount = RA_DailyRingLimit.countForDay(
          timesRingToday: fresh.TimesRingToday,
          timesRingDay: fresh.TimesRingDay,
          now: now,
          dayStartSeconds: routine.DayStartSeconds,
        );
        timesRingToday = priorCount + 1;
        timesRingDay = period;
      }

      // Daily cap only defers the next interval cycle, never an in-cycle snooze.
      final next = isEffectiveDismiss
          ? RA_DailyRingLimit.deferIfDailyLimitReached(
              proposed: calculated,
              maxTimesPerDay: routine.MaxTimesPerDayEnabled
                  ? routine.MaxTimesPerDay
                  : 0,
              timesRingToday: timesRingToday,
              timesRingDay: timesRingDay,
              now: now,
              dayStartSeconds: routine.DayStartSeconds,
            )
          : calculated;

      // CAS:
      // - Dismiss / Snooze / AutoSnooze: require a live ring.
      // - Skip while ringing: same IsRinging CAS so Dismiss cannot both win.
      // - Skip while idle: optimistic lock on the caller snapshot's
      //   NextTriggerTime (not the re-read) so a second Skip with the same
      //   advisory state cannot commit after the first already advanced it.
      final bool? ringingCas;
      final bool matchNext;
      if (requiresRinging || fresh.IsRinging) {
        ringingCas = true;
        matchNext = false;
      } else {
        ringingCas = null;
        matchNext = true;
      }

      final rows = await db.updateRoutineState(
        routineId,
        RoutineStatesCompanion(
          NextTriggerTime: Value(next),
          IsRinging: const Value(false),
          CurrentSnoozeCount: Value(
            isEffectiveDismiss ? 0 : fresh.CurrentSnoozeCount + 1,
          ),
          LastDismissedAt:
              isEffectiveDismiss ? Value(now) : const Value.absent(),
          TimesRingToday: shouldCountSkip
              ? Value(timesRingToday)
              : const Value.absent(),
          TimesRingDay: shouldCountSkip
              ? Value(timesRingDay)
              : const Value.absent(),
        ),
        requireIsRinging: ringingCas,
        matchNextTriggerTime: matchNext,
        nextTriggerTimeToMatch: matchNext ? state.NextTriggerTime : null,
      );
      if (rows == 0) return;

      int? timeSinceLastDismissal;
      if (isEffectiveDismiss && fresh.LastDismissedAt != null) {
        timeSinceLastDismissal =
            now.difference(fresh.LastDismissedAt!).inSeconds;
      }

      final logAction = _mapToLogAction(action);

      await db.insertLogEntry(
        LogEntriesCompanion(
          RoutineId: Value(routineId),
          Timestamp: Value(now),
          LogActionTypeCode: Value(logAction.index),
          TimeSinceLastDismissalSeconds: timeSinceLastDismissal != null
              ? Value(timeSinceLastDismissal)
              : const Value.absent(),
        ),
      );

      nextTrigger = next;
    });

    // Lost the race (another writer already cleared IsRinging) or missing state.
    if (nextTrigger == null) return;

    // Every action ends the current ring, so the watchdog armed for it and the
    // ongoing full-screen notification both belong to a cycle that is over.
    await _cancelWatchdog(routineId);
    await RA_NotificationService.cancelNotification(routineId);

    // Reschedule
    final dbPath = (await SharedPreferences.getInstance()).getString(
      _dbPathKey,
    );
    if (dbPath != null) {
      await scheduleNext(
        routineId: routineId,
        triggerTime: nextTrigger!,
        dbPath: dbPath,
        routineName: routine.Name,
      );
    }

    _pingUiIsolate(routineId);
  }

  static LogActionTypeCodeEnum _mapToLogAction(
    RA_AlarmActionTypeCodeEnum action,
  ) =>
      LogActionTypeCodeEnum.values[action.index];

  /// Sends a ping to the UI isolate via IsolateNameServer.
  static void _pingUiIsolate(int routineId) {
    final sendPort = IsolateNameServer.lookupPortByName(_portName);
    sendPort?.send(routineId);
  }

  /// Registers a receive port in the UI isolate to listen for pings.
  /// Closes any previous port/subscription first so hot restart does not leak.
  static void registerUiPort(void Function(dynamic) callback) {
    IsolateNameServer.removePortNameMapping(_portName);
    final previousSub = _uiPortSubscription;
    final previousPort = _uiReceivePort;
    _uiPortSubscription = null;
    _uiReceivePort = null;
    unawaited(previousSub?.cancel() ?? Future<void>.value());
    previousPort?.close();

    final receivePort = ReceivePort();
    _uiReceivePort = receivePort;
    IsolateNameServer.registerPortWithName(receivePort.sendPort, _portName);
    _uiPortSubscription = receivePort.listen(callback);
  }

  /// Triggers the alarm for [routineId] immediately if due or requested.
  static Future<void> triggerAlarm(int routineId) async {
    await _alarmCallback(_alarmIdBase + routineId);
  }

  /// Simulates background isolate execution of an alarm callback in automated test environments.
  @visibleForTesting
  static Future<void> simulateAlarmCallback(int routineId) async {
    await _alarmCallback(_alarmIdBase + routineId);
  }

  /// Simulates background isolate execution of a watchdog auto-snooze callback in automated test environments.
  @visibleForTesting
  static Future<void> simulateWatchdogCallback(int routineId) async {
    await _watchdogCallback(_watchdogIdBase + routineId);
  }
}
