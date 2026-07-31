import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/alarm_action_type_code.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';
import 'package:rolling_alarm/enums/log_action_type_code.dart';
import 'package:rolling_alarm/services/alarm_calculator.dart';
import 'package:rolling_alarm/services/audio.dart';
import 'package:rolling_alarm/services/daily_ring_limit.dart';
import 'package:rolling_alarm/services/notification.dart';
import 'package:rolling_alarm/services/weekday_schedule.dart';
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
            refreshWidget: false,
          );
        } catch (_) {
          // One bad routine must not block re-arming the rest.
        }
      }
      await RA_WidgetService.updateWidgetState(db: db);
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
    bool refreshWidget = true,
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

      // Refresh the pinned routine dashboard (not whichever routine scheduled).
      if (refreshWidget) {
        await RA_WidgetService.updateWidgetState();
      }
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

  static const String _alarmSoundChannel =
      'com.example.rolling_alarm/alarm_sound';

  /// Clears lock-screen overlay flags after Snooze / Dismiss ends a live ring.
  ///
  /// When the keyguard is still locked, native also backgrounds the activity
  /// so the lock screen returns without killing the Flutter engine. When the
  /// user was already in the unlocked app, the activity stays foregrounded.
  static Future<void> dismissAlarmUI() async {
    try {
      const channel = MethodChannel(_alarmSoundChannel);
      await channel.invokeMethod<void>('dismissAlarmUI');
    } catch (_) {
      // Channel absent in tests / headless isolates.
    }
  }

  /// Sets the device hardware alarm stream volume.
  ///
  /// [volumePercentage] is 0.0 (silent) to 1.0 (full STREAM_ALARM max).
  /// Moves the OS alarm volume in real time.
  static Future<void> setSystemAlarmVolume(double volumePercentage) async {
    try {
      const channel = MethodChannel(_alarmSoundChannel);
      await channel.invokeMethod<void>(
        'setSystemAlarmVolume',
        volumePercentage.clamp(0.0, 1.0),
      );
    } catch (_) {
      // Channel absent in tests / headless isolates / non-Android.
    }
  }

  /// Reads the current hardware alarm stream volume as 0.0 to 1.0.
  static Future<double> getSystemAlarmVolume() async {
    try {
      const channel = MethodChannel(_alarmSoundChannel);
      final result = await channel.invokeMethod<num>('getSystemAlarmVolume');
      if (result == null) return 1.0;
      return result.toDouble().clamp(0.0, 1.0);
    } catch (_) {
      return 1.0;
    }
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
    WidgetsFlutterBinding.ensureInitialized();
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
        await RA_WidgetService.updateWidgetState(db: db);
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
        if (!RA_WeekdaySchedule.isDateEnabled(routine.EnabledWeekdays, now)) {
          final deferred = RA_WeekdaySchedule.deferToEnabledDay(
            now,
            routine.EnabledWeekdays,
            dayStartSeconds: routine.DayStartSeconds,
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
            refreshWidget: false,
          );
          await RA_WidgetService.updateWidgetState(db: db);
          return;
        }

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
          final deferred = RA_WeekdaySchedule.deferToEnabledDay(
            RA_DailyRingLimit.nextCalendarDayStart(
              now,
              routine.DayStartSeconds,
            ),
            routine.EnabledWeekdays,
            dayStartSeconds: routine.DayStartSeconds,
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
            refreshWidget: false,
          );
          await RA_WidgetService.updateWidgetState(db: db);
          return;
        }
      }

      // Muted: count the ring (fresh only), silent-dismiss, reschedule. No UX.
      if (state.MutedAt != null) {
        await _handleMutedFire(
          routineId: routineId,
          db: db,
          routine: routine,
          state: state,
          dbPath: dbPath,
          now: now,
          isResumingFromSnooze: isResumingFromSnooze,
        );
        return;
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

      await db.insertActivityLog(
        routineId: routineId,
        action: LogActionTypeCodeEnum.Ring,
        timestamp: now,
      );

      // Wake UI / lock-screen paths BEFORE audio. just_audio init can hang or
      // fail on OEM devices; the ring page must still appear on time.
      // Prefs only: never post a local notification (full-page ring only).
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
          volume: routine.Volume,
          fadeIn: routine.FadeIn,
        );
      } catch (_) {
        // Ring UI wake prefs already set; audio can retry on ring page.
      }

      // Second ping in case the first raced ahead of Drift visibility.
      _pingUiIsolate(routineId);

      // Push dismissals / next time for the pinned routine without opening the app.
      await RA_WidgetService.updateWidgetState(db: db);
    } catch (_) {
      // Never let an unhandled exception kill the background isolate mid-ring.
    } finally {
      await db?.close();
    }
  }

  @pragma('vm:entry-point')
  static Future<void> _watchdogCallback(int alarmId) async {
    WidgetsFlutterBinding.ensureInitialized();
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
        await RA_WidgetService.updateWidgetState(db: db);
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
      // Weekday filter applies to dismiss/skip the same way.
      final next = isEffectiveDismiss
          ? RA_WeekdaySchedule.deferToEnabledDay(
              RA_DailyRingLimit.deferIfDailyLimitReached(
                proposed: calculated,
                maxTimesPerDay: routine.MaxTimesPerDayEnabled
                    ? routine.MaxTimesPerDay
                    : 0,
                timesRingToday: timesRingToday,
                timesRingDay: timesRingDay,
                now: now,
                dayStartSeconds: routine.DayStartSeconds,
              ),
              routine.EnabledWeekdays,
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
          LastDismissedAt: isEffectiveDismiss
              ? Value(now)
              : const Value.absent(),
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
        timeSinceLastDismissal = now
            .difference(fresh.LastDismissedAt!)
            .inSeconds;
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
    // native FGS / wake prefs both belong to a cycle that is over.
    await _cancelWatchdog(routineId);
    await RA_NotificationService.cancelNotification(routineId);

    // Drop lock-screen overlay (and background only if the keyguard is locked).
    // Must run after IsRinging is cleared so the ring presenter cannot re-foreground.
    if (action == RA_AlarmActionTypeCodeEnum.Dismiss ||
        action == RA_AlarmActionTypeCodeEnum.Snooze ||
        action == RA_AlarmActionTypeCodeEnum.AutoSnooze) {
      await dismissAlarmUI();
    }

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
        refreshWidget: false,
      );
    }

    // Recalculate dismissals_today / next_alarm_time for the pinned dashboard.
    await RA_WidgetService.updateWidgetState(db: db);

    _pingUiIsolate(routineId);
  }

  /// Pauses [routine]: cancels OS timers, freezes the countdown at the remaining
  /// duration, and marks the routine inactive so background fires are ignored.
  ///
  /// Clears mute. Day-start targets keep their absolute [NextTriggerTime];
  /// interval targets freeze remaining as `pausedAt + floor(remaining)`.
  ///
  /// If the routine is currently ringing, ends the ring and freezes the next
  /// interval trigger (same calculation as dismiss) without scheduling it.
  static Future<void> pauseRoutine({
    required int routineId,
    required RA_Database db,
    required RoutineModel routine,
    required String dbPath,
  }) async {
    final now = DateTime.now();
    final state = await db.getRoutineState(routineId);

    await cancel(routineId);
    await _cancelWatchdog(routineId);
    await RA_NotificationService.cancelNotification(routineId);

    if (state?.IsRinging == true) {
      await RA_AudioService.stopAlarm();
      await stopNativeRinging(routineId);
      await dismissAlarmUI();
    }

    DateTime? next = state?.NextTriggerTime;
    var snoozeCount = state?.CurrentSnoozeCount ?? 0;

    if (state?.IsRinging == true) {
      final compensation = DriftCompensationTypeCodeEnum
          .values[routine.DriftCompensationTypeCode];
      final calculated = RA_AlarmCalculator.calculateNextTrigger(
        Action: RA_AlarmActionTypeCodeEnum.Dismiss,
        Compensation: compensation,
        IntervalSeconds: routine.IntervalSeconds,
        SnoozeSeconds: routine.SnoozeSeconds,
        InitialRingTime: state?.InitialRingTime ?? now,
        Now: now,
      );
      next = RA_WeekdaySchedule.deferToEnabledDay(
        RA_DailyRingLimit.deferIfDailyLimitReached(
          proposed: calculated,
          maxTimesPerDay: routine.MaxTimesPerDayEnabled
              ? routine.MaxTimesPerDay
              : 0,
          timesRingToday: state?.TimesRingToday ?? 0,
          timesRingDay: state?.TimesRingDay,
          now: now,
          dayStartSeconds: routine.DayStartSeconds,
        ),
        routine.EnabledWeekdays,
        dayStartSeconds: routine.DayStartSeconds,
      );
      snoozeCount = 0;
    }

    // Drift stores DateTimes as whole Unix seconds, so a raw PausedAt would be
    // truncated toward the past and inflate remaining by almost 1s vs the live
    // countdown (which uses sub-second DateTime.now). Snap both timestamps to
    // second precision with remaining = floor(live remaining).
    // Day-start targets keep their absolute wall-clock NextTriggerTime.
    final pausedAt = _driftSecondFloor(now);
    if (next != null) {
      final preserveAbsolute = RA_DailyRingLimit.isPeriodStartTrigger(
        trigger: next,
        dayStartSeconds: routine.DayStartSeconds,
      );
      if (!preserveAbsolute) {
        final remainingSeconds = next.difference(now).inSeconds;
        final whole = remainingSeconds < 0 ? 0 : remainingSeconds;
        next = pausedAt.add(Duration(seconds: whole));
      }
    }

    await db.updateRoutine(
      RoutinesCompanion(Id: Value(routineId), IsActive: const Value(false)),
    );

    if (state != null) {
      await db.updateRoutineState(
        routineId,
        RoutineStatesCompanion(
          IsRinging: const Value(false),
          PausedAt: Value(pausedAt),
          MutedAt: const Value(null),
          NextTriggerTime: Value(next),
          CurrentSnoozeCount: Value(snoozeCount),
        ),
      );
    }

    await db.insertActivityLog(
      routineId: routineId,
      action: LogActionTypeCodeEnum.Pause,
      timestamp: now,
    );

    await RA_WidgetService.updateWidgetState(db: db);
    _pingUiIsolate(routineId);
  }

  /// Resumes a paused routine: restores [IsActive], applies pause-resume rules
  /// for the next trigger, and re-arms the OS alarm.
  ///
  /// Interval targets shift by frozen remaining. Day-start targets that are
  /// still ahead keep their absolute time; missed day-starts use
  /// [RA_DailyRingLimit.earliestResumeAfterMissedDayStart].
  ///
  /// Pass [logHistory] false when resume is an internal step of another
  /// user action (e.g. mute clears pause first).
  static Future<void> resumeRoutine({
    required int routineId,
    required RA_Database db,
    required RoutineModel routine,
    required String dbPath,
    bool logHistory = true,
  }) async {
    final now = DateTime.now();
    final state = await db.getRoutineState(routineId);
    final pausedAt = state?.PausedAt;
    final next = state?.NextTriggerTime;

    DateTime? newNext;
    if (next != null && pausedAt != null) {
      final wasDayStart = RA_DailyRingLimit.isPeriodStartTrigger(
        trigger: next,
        dayStartSeconds: routine.DayStartSeconds,
      );
      if (wasDayStart) {
        if (next.isAfter(now)) {
          newNext = next;
        } else {
          newNext = RA_DailyRingLimit.earliestResumeAfterMissedDayStart(
            now: now,
            intervalSeconds: routine.IntervalSeconds,
            dayStartSeconds: routine.DayStartSeconds,
          );
        }
      } else {
        final remainingSeconds = next.difference(pausedAt).inSeconds;
        final whole = remainingSeconds < 0 ? 0 : remainingSeconds;
        newNext = now.add(Duration(seconds: whole));
      }
    } else if (next != null && next.isAfter(now)) {
      newNext = next;
    }

    if (newNext != null) {
      newNext = RA_WeekdaySchedule.deferToEnabledDay(
        newNext,
        routine.EnabledWeekdays,
        dayStartSeconds: routine.DayStartSeconds,
      );
    }

    await db.updateRoutine(
      RoutinesCompanion(Id: Value(routineId), IsActive: const Value(true)),
    );

    if (state != null) {
      await db.updateRoutineState(
        routineId,
        RoutineStatesCompanion(
          PausedAt: const Value(null),
          NextTriggerTime: Value(newNext),
        ),
      );
    }

    if (newNext != null) {
      await scheduleNext(
        routineId: routineId,
        triggerTime: newNext,
        dbPath: dbPath,
        routineName: routine.Name,
        refreshWidget: false,
      );
    }

    if (logHistory) {
      await db.insertActivityLog(
        routineId: routineId,
        action: LogActionTypeCodeEnum.Resume,
        timestamp: now,
      );
    }

    await RA_WidgetService.updateWidgetState(db: db);
    _pingUiIsolate(routineId);
  }

  /// Mutes [routine]: schedule keeps running; fires auto-dismiss and count.
  ///
  /// Clears pause first (via [resumeRoutine]). If currently ringing, silent
  /// dismisses then remains muted.
  static Future<void> muteRoutine({
    required int routineId,
    required RA_Database db,
    required RoutineModel routine,
    required String dbPath,
  }) async {
    final state = await db.getRoutineState(routineId);

    if (state?.PausedAt != null) {
      await resumeRoutine(
        routineId: routineId,
        db: db,
        routine: routine,
        dbPath: dbPath,
        logHistory: false,
      );
    }

    final fresh = await db.getRoutineState(routineId);
    if (fresh?.IsRinging == true) {
      await RA_AudioService.stopAlarm();
      await stopNativeRinging(routineId);
      await handleTransition(
        action: RA_AlarmActionTypeCodeEnum.Dismiss,
        routineId: routineId,
        db: db,
        routine: routine,
        state: fresh!,
      );
    }

    final mutedAt = _driftSecondFloor(DateTime.now());
    await db.updateRoutine(
      RoutinesCompanion(Id: Value(routineId), IsActive: const Value(true)),
    );
    if (fresh != null || state != null) {
      await db.updateRoutineState(
        routineId,
        RoutineStatesCompanion(
          MutedAt: Value(mutedAt),
          PausedAt: const Value(null),
        ),
      );
    }

    await db.insertActivityLog(
      routineId: routineId,
      action: LogActionTypeCodeEnum.Mute,
      timestamp: mutedAt,
    );

    await RA_WidgetService.updateWidgetState(db: db);
    _pingUiIsolate(routineId);
  }

  /// Clears mute; countdown and next fire are unchanged.
  static Future<void> unmuteRoutine({
    required int routineId,
    required RA_Database db,
  }) async {
    final now = DateTime.now();
    await db.updateRoutineState(
      routineId,
      const RoutineStatesCompanion(MutedAt: Value(null)),
    );
    await db.insertActivityLog(
      routineId: routineId,
      action: LogActionTypeCodeEnum.Unmute,
      timestamp: now,
    );
    await RA_WidgetService.updateWidgetState(db: db);
    _pingUiIsolate(routineId);
  }

  /// Restores a soft-deleted routine: clears [Deleted], arms a fresh next
  /// trigger (same rules as create), and re-schedules the OS alarm.
  ///
  /// No-ops when the routine is missing or already live.
  static Future<bool> recoverRoutine({
    required int routineId,
    required RA_Database db,
    required String dbPath,
  }) async {
    final routine = await db.getRoutineById(routineId);
    if (!routine.Deleted) return false;

    final next = RA_DailyRingLimit.initialTriggerTime(
      now: DateTime.now(),
      interval: Duration(seconds: routine.IntervalSeconds),
      maxTimesPerDayEnabled: routine.MaxTimesPerDayEnabled,
      dayStartSeconds: routine.DayStartSeconds,
      enabledWeekdays: routine.EnabledWeekdays,
    );

    final recovered = await db.recoverRoutine(
      id: routineId,
      nextTriggerTime: next,
    );
    if (!recovered) return false;

    await scheduleNext(
      routineId: routineId,
      triggerTime: next,
      dbPath: dbPath,
      routineName: routine.Name,
      refreshWidget: false,
    );
    await RA_WidgetService.updateWidgetState(db: db);
    _pingUiIsolate(routineId);
    return true;
  }

  /// Zeros today's ring counter for the current day period.
  ///
  /// When the prior count had exhausted the daily cap and [NextTriggerTime]
  /// was parked on a day-start boundary, retargets to [now] plus the routine
  /// interval and re-arms the OS timer so alarms can resume today.
  static Future<void> resetTodayCounter({
    required int routineId,
    required RA_Database db,
    required RoutineModel routine,
    required String dbPath,
  }) async {
    final now = DateTime.now();
    final state = await db.getRoutineState(routineId);
    final period = RA_DailyRingLimit.periodStart(now, routine.DayStartSeconds);
    final previousNext = state?.NextTriggerTime;

    DateTime? next = RA_DailyRingLimit.retargetNextAfterCounterReset(
      previousNext: previousNext,
      priorTimesRingToday: state?.TimesRingToday ?? 0,
      timesRingDay: state?.TimesRingDay,
      maxTimesPerDayEnabled: routine.MaxTimesPerDayEnabled,
      maxTimesPerDay: routine.MaxTimesPerDay,
      now: now,
      intervalSeconds: routine.IntervalSeconds,
      dayStartSeconds: routine.DayStartSeconds,
      enabledWeekdays: routine.EnabledWeekdays,
    );

    // While paused, store the new interval relative to PausedAt so resume
    // shifts by frozen remaining instead of inflating past the pause gap.
    final pausedAt = state?.PausedAt;
    final nextChanged =
        next != null &&
        (previousNext == null ||
            next.millisecondsSinceEpoch != previousNext.millisecondsSinceEpoch);
    if (nextChanged && pausedAt != null) {
      next = RA_WeekdaySchedule.deferToEnabledDay(
        RA_DailyRingLimit.deferIfDailyLimitReached(
          proposed: pausedAt.add(Duration(seconds: routine.IntervalSeconds)),
          maxTimesPerDay: routine.MaxTimesPerDayEnabled
              ? routine.MaxTimesPerDay
              : 0,
          timesRingToday: 0,
          timesRingDay: period,
          now: now,
          dayStartSeconds: routine.DayStartSeconds,
        ),
        routine.EnabledWeekdays,
        dayStartSeconds: routine.DayStartSeconds,
      );
    }

    await db.updateRoutineState(
      routineId,
      RoutineStatesCompanion(
        TimesRingToday: const Value(0),
        TimesRingDay: Value(period),
        NextTriggerTime: nextChanged ? Value(next) : const Value.absent(),
      ),
    );

    await db.insertActivityLog(
      routineId: routineId,
      action: LogActionTypeCodeEnum.ResetCounter,
      timestamp: now,
    );

    if (nextChanged && next != null && routine.IsActive) {
      await scheduleNext(
        routineId: routineId,
        triggerTime: next,
        dbPath: dbPath,
        routineName: routine.Name,
        refreshWidget: false,
      );
    }
    await RA_WidgetService.updateWidgetState(db: db);
    _pingUiIsolate(routineId);
  }

  /// Silent muted fire: count (fresh rings only), dismiss-schedule next, no UX.
  static Future<void> _handleMutedFire({
    required int routineId,
    required RA_Database db,
    required RoutineModel routine,
    required RoutineStateModel state,
    required String dbPath,
    required DateTime now,
    required bool isResumingFromSnooze,
  }) async {
    final compensation =
        DriftCompensationTypeCodeEnum.values[routine.DriftCompensationTypeCode];
    final period = RA_DailyRingLimit.periodStart(now, routine.DayStartSeconds);
    final priorCount = RA_DailyRingLimit.countForDay(
      timesRingToday: state.TimesRingToday,
      timesRingDay: state.TimesRingDay,
      now: now,
      dayStartSeconds: routine.DayStartSeconds,
    );

    // Snooze-resume while muted: dismiss without counting again.
    final shouldCount = !isResumingFromSnooze;
    final timesRingToday = shouldCount ? priorCount + 1 : state.TimesRingToday;
    final timesRingDay = shouldCount ? period : state.TimesRingDay;
    final initialRing = isResumingFromSnooze
        ? (state.InitialRingTime ?? now)
        : now;

    final calculated = RA_AlarmCalculator.calculateNextTrigger(
      Action: RA_AlarmActionTypeCodeEnum.Dismiss,
      Compensation: compensation,
      IntervalSeconds: routine.IntervalSeconds,
      SnoozeSeconds: routine.SnoozeSeconds,
      InitialRingTime: initialRing,
      Now: now,
    );
    final next = RA_WeekdaySchedule.deferToEnabledDay(
      RA_DailyRingLimit.deferIfDailyLimitReached(
        proposed: calculated,
        maxTimesPerDay: routine.MaxTimesPerDayEnabled
            ? routine.MaxTimesPerDay
            : 0,
        timesRingToday: timesRingToday,
        timesRingDay: timesRingDay,
        now: now,
        dayStartSeconds: routine.DayStartSeconds,
      ),
      routine.EnabledWeekdays,
      dayStartSeconds: routine.DayStartSeconds,
    );

    int? timeSinceLastDismissal;
    if (state.LastDismissedAt != null) {
      timeSinceLastDismissal = now.difference(state.LastDismissedAt!).inSeconds;
    }

    await db.transaction(() async {
      await db.updateRoutineState(
        routineId,
        RoutineStatesCompanion(
          NextTriggerTime: Value(next),
          IsRinging: const Value(false),
          CurrentSnoozeCount: const Value(0),
          LastDismissedAt: Value(now),
          InitialRingTime: shouldCount ? Value(now) : const Value.absent(),
          TimesRingToday: shouldCount
              ? Value(timesRingToday)
              : const Value.absent(),
          TimesRingDay: shouldCount
              ? Value(timesRingDay)
              : const Value.absent(),
        ),
        requireIsRinging: false,
      );

      await db.insertLogEntry(
        LogEntriesCompanion(
          RoutineId: Value(routineId),
          Timestamp: Value(now),
          LogActionTypeCode: Value(LogActionTypeCodeEnum.Dismiss.index),
          TimeSinceLastDismissalSeconds: timeSinceLastDismissal != null
              ? Value(timeSinceLastDismissal)
              : const Value.absent(),
          WasMuted: const Value(true),
        ),
      );
    });

    await scheduleNext(
      routineId: routineId,
      triggerTime: next,
      dbPath: dbPath,
      routineName: routine.Name,
      refreshWidget: false,
    );
    await RA_WidgetService.updateWidgetState(db: db);
    _pingUiIsolate(routineId);
  }

  /// Floors [value] to the same whole-second instant Drift persists for DateTimes.
  static DateTime _driftSecondFloor(DateTime value) =>
      DateTime.fromMillisecondsSinceEpoch(
        (value.millisecondsSinceEpoch ~/ 1000) * 1000,
      );

  static LogActionTypeCodeEnum _mapToLogAction(
    RA_AlarmActionTypeCodeEnum action,
  ) => switch (action) {
    RA_AlarmActionTypeCodeEnum.Dismiss => LogActionTypeCodeEnum.Dismiss,
    RA_AlarmActionTypeCodeEnum.Snooze => LogActionTypeCodeEnum.Snooze,
    RA_AlarmActionTypeCodeEnum.Skip => LogActionTypeCodeEnum.Skip,
    RA_AlarmActionTypeCodeEnum.AutoSnooze => LogActionTypeCodeEnum.AutoSnooze,
  };

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
