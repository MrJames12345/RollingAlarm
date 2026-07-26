import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/navigation/routes.dart';
import 'package:rolling_alarm/pages/alarm_ring.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';

/// Presents [AlarmRingPage] on the root navigator whenever a routine is ringing.
///
/// Lives above [HomePage] so Logs, Edit, and other routes cannot cover the
/// alarm UI. Re-opens the ring page if it is closed while [IsRinging] is still
/// true (for example after a system back gesture on older platforms).
class RA_AlarmRingPresenter extends ConsumerStatefulWidget {
  final Widget child;

  const RA_AlarmRingPresenter({super.key, required this.child});

  @override
  ConsumerState<RA_AlarmRingPresenter> createState() =>
      _RA_AlarmRingPresenterState();
}

class _RA_AlarmRingPresenterState extends ConsumerState<RA_AlarmRingPresenter>
    with WidgetsBindingObserver {
  /// True from the moment a ring push is accepted until that route pops.
  bool _ringPushInFlight = false;

  /// Routine currently shown (or being opened) on [AlarmRingPage].
  int? _openRingRoutineId;

  Timer? _foregroundWatchdog;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_ensureRingPageVisible());
      // Native UI setAlarmClock channel is only live after the engine attaches.
      unawaited(
        RA_AlarmService.syncAlarmUiSchedules(ref.read(RA_DatabaseProvider)),
      );
    });
    _foregroundWatchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_checkForegroundAlarms());
    });
  }

  @override
  void dispose() {
    _foregroundWatchdog?.cancel();
    _foregroundWatchdog = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_ensureRingPageVisible());
      unawaited(_checkForegroundAlarms());
    }
  }

  Future<void> _checkForegroundAlarms() async {
    // Recover a missed UI ping: Drift may already have IsRinging=true while
    // the ring page never opened (e.g. audio hung before the isolate ping).
    if (!_ringPushInFlight && _openRingRoutineId == null) {
      try {
        var states = ref.read(RingingRoutineStatesProvider).valueOrNull;
        if (states == null || states.isEmpty) {
          final db = ref.read(RA_DatabaseProvider);
          states = await db.getRingingRoutineStates();
        }
        if (states != null && states.isNotEmpty) {
          await _ensureRingPageVisible();
        }
      } catch (_) {}
    }
    if (_ringPushInFlight || _openRingRoutineId != null) return;
    await _triggerDueAlarms();
  }

  Future<void> _ensureRingPageVisible() async {
    List<RoutineStateModel>? states = ref
        .read(RingingRoutineStatesProvider)
        .valueOrNull;
    if (states == null) {
      try {
        final db = ref.read(RA_DatabaseProvider);
        states = await db.getRingingRoutineStates();
      } catch (_) {}
    }
    if (states == null || states.isEmpty) {
      // Activity may have been woken by setAlarmClock before the Dart
      // callback committed IsRinging. Trigger any due alarms first, then
      // wait briefly before clearing lock-screen overlay flags.
      await _triggerDueAlarms();
      try {
        final db = ref.read(RA_DatabaseProvider);
        states = await db.getRingingRoutineStates();
      } catch (_) {}
    }
    if (states == null || states.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      try {
        final db = ref.read(RA_DatabaseProvider);
        states = await db.getRingingRoutineStates();
      } catch (_) {}
    }
    if (states == null || states.isEmpty) {
      // Only clear after the grace wait; native also ignores early clears.
      try {
        const channel = MethodChannel('com.example.rolling_alarm/alarm_sound');
        await channel.invokeMethod('clearLockScreenFlags');
      } catch (_) {}
      return;
    }
    try {
      const channel = MethodChannel('com.example.rolling_alarm/alarm_sound');
      await channel.invokeMethod('bringToForeground');
    } catch (_) {}
    await _presentRingPage(states.first);
  }

  Future<void> _triggerDueAlarms() async {
    try {
      final db = ref.read(RA_DatabaseProvider);
      final routines = await db.getActiveRoutines();
      final now = DateTime.now();
      for (final routine in routines) {
        final state = await db.getRoutineState(routine.Id);
        if (state != null &&
            !state.IsRinging &&
            state.NextTriggerTime != null) {
          if (!state.NextTriggerTime!.isAfter(now)) {
            await RA_AlarmService.triggerAlarm(routine.Id);
            break;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _presentRingPage(RoutineStateModel ringingState) async {
    if (_ringPushInFlight || _openRingRoutineId == ringingState.RoutineId) {
      return;
    }
    final nav = RA_navigatorKey.currentState;
    if (nav == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_ensureRingPageVisible());
      });
      return;
    }

    _ringPushInFlight = true;
    _openRingRoutineId = ringingState.RoutineId;
    try {
      final db = ref.read(RA_DatabaseProvider);
      final routine = await db.getRoutineById(ringingState.RoutineId);
      if (!mounted) return;

      final still = await db.getRoutineState(routine.Id);
      if (still == null || !still.IsRinging) return;

      final navigator = RA_navigatorKey.currentState;
      if (navigator == null) return;

      try {
        const channel = MethodChannel('com.example.rolling_alarm/alarm_sound');
        await channel.invokeMethod('bringToForeground');
      } catch (_) {}

      await navigator.push(
        RA_Routes.alarmRing(
          AlarmRingPage(
            routineId: routine.Id,
            routineName: routine.Name,
            audioUri: routine.AudioUri,
            vibrate: routine.Vibrate,
          ),
        ),
      );
    } finally {
      _ringPushInFlight = false;
      _openRingRoutineId = null;
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_ensureRingPageVisible());
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(RingingRoutineStatesProvider, (previous, next) {
      next.whenData((states) {
        if (states.isEmpty) {
          if (!_ringPushInFlight) {
            _openRingRoutineId = null;
          }
          try {
            const channel = MethodChannel(
              'com.example.rolling_alarm/alarm_sound',
            );
            unawaited(channel.invokeMethod('clearLockScreenFlags'));
          } catch (_) {}
          return;
        }
        try {
          const channel = MethodChannel(
            'com.example.rolling_alarm/alarm_sound',
          );
          unawaited(channel.invokeMethod('bringToForeground'));
        } catch (_) {}
        unawaited(_presentRingPage(states.first));
      });
    });

    return widget.child;
  }
}
