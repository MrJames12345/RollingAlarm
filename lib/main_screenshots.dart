/// Google Play Store screenshot entry point. Never shipped: release builds use
/// `lib/main.dart`. Built and driven by `scripts/capture_play_screenshots.sh`.
///
/// Every launch wipes the database and preferences, seeds a fixed set of demo
/// routines and log history relative to the current clock, then opens the
/// scene named by the FlutterActivity `route` intent extra:
///
/// ```
/// adb shell am start -n com.casellaweb.rolling_alarm/.MainActivity \
///   --es route "/dashboard"
/// ```
///
/// Scenes: dashboard, ringing, editor, summary, logs, settings. Every scene
/// renders in the dark theme.
///
/// Once the scene has settled, `RA_SCREENSHOT_READY <route>` is printed to
/// logcat so the host script knows when to capture.
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
import 'package:rolling_alarm/models/alarm_sound.dart';
import 'package:rolling_alarm/navigation/routes.dart';
import 'package:rolling_alarm/pages/logs.dart';
import 'package:rolling_alarm/pages/routine_edit.dart';
import 'package:rolling_alarm/pages/routine_summary.dart';
import 'package:rolling_alarm/pages/settings.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/daily_ring_limit.dart';
import 'package:rolling_alarm/services/settings.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum RA_ScreenshotScene { dashboard, ringing, editor, summary, logs, settings }

/// Time allowed after the scene opens for page fades and runtime font loading
/// to finish before capture.
const Duration _settleDelay = Duration(milliseconds: 2500);

/// Editor section scrolled flush to the top of the editor scene.
const String _editorTopSection = 'Interval';

/// Point in the ring page's repeating pulse where the alarm icon is still
/// legible under its glow. The pulse is frozen here so every capture matches.
const double _ringPulseFreezeValue = 0.35;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final route = PlatformDispatcher.instance.defaultRouteName;
  final uri = Uri.parse(route);
  final scene = RA_ScreenshotScene.values.firstWhere(
    (s) => uri.pathSegments.isNotEmpty && s.name == uri.pathSegments.first,
    orElse: () => RA_ScreenshotScene.dashboard,
  );
  const themeMode = AppThemeModeEnum.Dark;

  final dbPath = await RA_Database.resolveDatabasePath();
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  await RA_AlarmService.persistDatabasePath(dbPath);
  await RA_SettingsService.setThemeMode(themeMode);

  final database = RA_Database();
  final demo = await _seedDemoData(
    database,
    ringing: scene == RA_ScreenshotScene.ringing,
  );

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Keep the status bar but hide the navigation bar, which also hides the
  // pinned launcher taskbar on tablet sized displays.
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top],
  );
  RA_ColourStyles.apply(themeMode);
  SystemChrome.setSystemUIOverlayStyle(RA_AppTheme.systemUiOverlayStyle());

  runApp(
    ProviderScope(
      overrides: [RA_DatabaseProvider.overrideWithValue(database)],
      child: RollingAlarmApp(dbPath: dbPath),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback(
    (_) => unawaited(_openScene(scene, route, database, dbPath, demo)),
  );
}

Future<void> _openScene(
  RA_ScreenshotScene scene,
  String route,
  RA_Database database,
  String dbPath,
  _DemoRoutineIds demo,
) async {
  var navigator = RA_navigatorKey.currentState;
  while (navigator == null) {
    await WidgetsBinding.instance.endOfFrame;
    navigator = RA_navigatorKey.currentState;
  }

  final medication = await database.getRoutineById(demo.medication);
  final page = switch (scene) {
    // Dashboard is the home route; ringing is opened by RA_AlarmRingPresenter.
    RA_ScreenshotScene.dashboard || RA_ScreenshotScene.ringing => null,
    RA_ScreenshotScene.editor => RoutineEditPage(
      dbPath: dbPath,
      existingRoutine: medication,
    ),
    RA_ScreenshotScene.summary => RoutineSummaryPage(
      routineId: medication.Id,
      dbPath: dbPath,
    ),
    RA_ScreenshotScene.logs => LogsPage(dbPath: dbPath),
    RA_ScreenshotScene.settings => SettingsPage(dbPath: dbPath),
  };
  if (page != null) {
    unawaited(navigator.push(RA_Routes.fade(page)));
  }

  await Future<void>.delayed(_settleDelay);
  if (scene == RA_ScreenshotScene.editor) {
    final section = _findText(_editorTopSection);
    if (section != null) {
      await Scrollable.ensureVisible(section);
    }
  }
  if (scene == RA_ScreenshotScene.ringing) {
    _freezeRingPulse();
  }
  await WidgetsBinding.instance.endOfFrame;
  debugPrint('RA_SCREENSHOT_READY $route');
}

/// The pulse widget is private to `alarm_ring.dart`, so it is matched by type
/// name and its public `pulse` field is read dynamically.
void _freezeRingPulse() {
  void visit(Element element) {
    final widget = element.widget;
    if (widget.runtimeType.toString() == '_RingPulseIcon') {
      final Object? pulse = (widget as dynamic).pulse;
      if (pulse is CurvedAnimation && pulse.parent is AnimationController) {
        (pulse.parent as AnimationController)
          ..stop()
          ..value = _ringPulseFreezeValue;
      }
      return;
    }
    element.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
}

Element? _findText(String text) {
  Element? found;
  void visit(Element element) {
    if (found != null) return;
    final widget = element.widget;
    if (widget is Text && widget.data == text) {
      found = element;
      return;
    }
    element.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return found;
}

class _DemoRoutineIds {
  final int medication;
  final int hydrate;
  final int stretch;
  final int eyeRest;

  const _DemoRoutineIds({
    required this.medication,
    required this.hydrate,
    required this.stretch,
    required this.eyeRest,
  });
}

DateTime _wholeSecond(DateTime value) => DateTime.fromMillisecondsSinceEpoch(
  value.millisecondsSinceEpoch ~/ 1000 * 1000,
);

/// Replaces all data with six routines that together show every home card
/// state except ringing (which opens the full screen ring page instead).
/// Home lists by creation date, and only the first three cards fit on a phone,
/// so those carry the most distinct states: a daily capped countdown, a paused
/// routine with a frozen countdown, and a muted weekday routine. The plain
/// Hydrate countdown is fourth and is the routine that rings. Posture Check
/// and Vitamins (daily limit reached) fill the taller tablet dashboards.
///
/// All trigger times are in the future so nothing fires during capture.
Future<_DemoRoutineIds> _seedDemoData(
  RA_Database db, {
  required bool ringing,
}) async {
  final now = _wholeSecond(DateTime.now());
  const dayStart = 6 * 3600;
  final today = RA_DailyRingLimit.periodStart(now, dayStart);
  final silent = RA_AlarmSound.silent.encode();

  return db.transaction(() async {
    await db.delete(db.logEntries).go();
    await db.delete(db.routineStates).go();
    await db.delete(db.routines).go();

    final medicationCreated = now.subtract(const Duration(days: 12));
    final medication = await db.insertRoutine(
      RoutinesCompanion.insert(
        Name: 'Medication',
        IntervalSeconds: 8 * 3600,
        SnoozeSeconds: const Value(10 * 60),
        DriftCompensationTypeCode:
            DriftCompensationTypeCodeEnum.InitialRing.index,
        MaxTimesPerDayEnabled: const Value(true),
        MaxTimesPerDay: const Value(3),
        DayStartSeconds: const Value(dayStart),
        Volume: const Value(70),
        FadeIn: const Value(true),
        CreatedAt: Value(medicationCreated),
      ),
    );
    final medicationRang = now.subtract(const Duration(hours: 1));
    await db.insertRoutineState(
      RoutineStatesCompanion.insert(
        RoutineId: medication,
        NextTriggerTime: Value(medicationRang.add(const Duration(hours: 8))),
        InitialRingTime: Value(medicationRang),
        TimesRingToday: const Value(1),
        TimesRingDay: Value(today),
        LastDismissedAt: Value(now.subtract(const Duration(minutes: 50))),
      ),
    );

    // Silent and without vibration so the ringing scene makes no noise.
    final hydrateCreated = now.subtract(const Duration(days: 3));
    final hydrate = await db.insertRoutine(
      RoutinesCompanion.insert(
        Name: 'Hydrate',
        IntervalSeconds: 3600,
        SnoozeSeconds: const Value(5 * 60),
        DriftCompensationTypeCode:
            DriftCompensationTypeCodeEnum.ActualDismissal.index,
        DayStartSeconds: const Value(dayStart),
        AudioUri: Value(silent),
        Vibrate: const Value(false),
        CreatedAt: Value(hydrateCreated),
      ),
    );
    await db.insertRoutineState(
      ringing
          ? RoutineStatesCompanion.insert(
              RoutineId: hydrate,
              NextTriggerTime: Value(now),
              InitialRingTime: Value(now),
              IsRinging: const Value(true),
              TimesRingToday: const Value(3),
              TimesRingDay: Value(today),
            )
          : RoutineStatesCompanion.insert(
              RoutineId: hydrate,
              NextTriggerTime: Value(
                now.add(const Duration(minutes: 42, seconds: 18)),
              ),
              TimesRingToday: const Value(2),
              TimesRingDay: Value(today),
              LastDismissedAt: Value(
                now.subtract(const Duration(minutes: 17, seconds: 42)),
              ),
            ),
    );

    // Monday to Friday so the weekday strip shows on its card.
    final stretchCreated = now.subtract(const Duration(days: 6));
    final stretch = await db.insertRoutine(
      RoutinesCompanion.insert(
        Name: 'Stretch Break',
        IntervalSeconds: 90 * 60,
        SnoozeSeconds: const Value(5 * 60),
        DriftCompensationTypeCode:
            DriftCompensationTypeCodeEnum.ActualDismissal.index,
        DayStartSeconds: const Value(dayStart),
        EnabledWeekdays: const Value(0x1F),
        CreatedAt: Value(stretchCreated),
      ),
    );
    await db.insertRoutineState(
      RoutineStatesCompanion.insert(
        RoutineId: stretch,
        NextTriggerTime: Value(now.add(const Duration(minutes: 66))),
        TimesRingToday: const Value(1),
        TimesRingDay: Value(today),
        MutedAt: Value(now.subtract(const Duration(minutes: 26))),
        LastDismissedAt: Value(now.subtract(const Duration(minutes: 24))),
      ),
    );

    final eyeRestCreated = now.subtract(const Duration(days: 9));
    final eyeRest = await db.insertRoutine(
      RoutinesCompanion.insert(
        Name: 'Eye Rest',
        IntervalSeconds: 20 * 60,
        SnoozeSeconds: const Value(2 * 60),
        DriftCompensationTypeCode:
            DriftCompensationTypeCodeEnum.ActualDismissal.index,
        DayStartSeconds: const Value(dayStart),
        Volume: const Value(40),
        IsActive: const Value(false),
        CreatedAt: Value(eyeRestCreated),
      ),
    );
    final eyeRestPaused = now.subtract(const Duration(minutes: 5));
    await db.insertRoutineState(
      RoutineStatesCompanion.insert(
        RoutineId: eyeRest,
        NextTriggerTime: Value(
          eyeRestPaused.add(const Duration(minutes: 12, seconds: 40)),
        ),
        PausedAt: Value(eyeRestPaused),
        TimesRingToday: const Value(2),
        TimesRingDay: Value(today),
      ),
    );

    // The last two routines only fit on tablet sized dashboards, which would
    // otherwise leave the lower part of the screen empty.
    final postureCreated = now.subtract(const Duration(days: 2));
    final posture = await db.insertRoutine(
      RoutinesCompanion.insert(
        Name: 'Posture Check',
        IntervalSeconds: 45 * 60,
        SnoozeSeconds: const Value(3 * 60),
        DriftCompensationTypeCode:
            DriftCompensationTypeCodeEnum.ActualDismissal.index,
        DayStartSeconds: const Value(dayStart),
        CreatedAt: Value(postureCreated),
      ),
    );
    await db.insertRoutineState(
      RoutineStatesCompanion.insert(
        RoutineId: posture,
        NextTriggerTime: Value(
          now.add(const Duration(minutes: 18, seconds: 30)),
        ),
        TimesRingToday: const Value(1),
        TimesRingDay: Value(today),
        LastDismissedAt: Value(
          now.subtract(const Duration(minutes: 26, seconds: 30)),
        ),
      ),
    );

    // Daily limit already reached, so the next ring is tomorrow's day start.
    final vitaminsCreated = now.subtract(const Duration(days: 1));
    final vitamins = await db.insertRoutine(
      RoutinesCompanion.insert(
        Name: 'Vitamins',
        IntervalSeconds: 30 * 60,
        SnoozeSeconds: const Value(10 * 60),
        DriftCompensationTypeCode:
            DriftCompensationTypeCodeEnum.InitialRing.index,
        MaxTimesPerDayEnabled: const Value(true),
        MaxTimesPerDay: const Value(2),
        DayStartSeconds: const Value(dayStart),
        CreatedAt: Value(vitaminsCreated),
      ),
    );
    await db.insertRoutineState(
      RoutineStatesCompanion.insert(
        RoutineId: vitamins,
        NextTriggerTime: Value(
          DateTime(today.year, today.month, today.day + 1, today.hour),
        ),
        TimesRingToday: const Value(2),
        TimesRingDay: Value(today),
        LastDismissedAt: Value(now.subtract(const Duration(minutes: 29))),
      ),
    );

    Future<void> log(
      int routineId,
      LogActionTypeCodeEnum action,
      Duration ago, {
      Duration? sinceLastDismissal,
      bool wasMuted = false,
    }) {
      return db.insertLogEntry(
        LogEntriesCompanion.insert(
          RoutineId: routineId,
          Timestamp: now.subtract(ago),
          LogActionTypeCode: action.index,
          TimeSinceLastDismissalSeconds: Value(sinceLastDismissal?.inSeconds),
          WasMuted: Value(wasMuted),
        ),
      );
    }

    await log(
      medication,
      LogActionTypeCodeEnum.Create,
      now.difference(medicationCreated),
    );
    await log(
      hydrate,
      LogActionTypeCodeEnum.Create,
      now.difference(hydrateCreated),
    );
    await log(
      stretch,
      LogActionTypeCodeEnum.Create,
      now.difference(stretchCreated),
    );
    await log(
      eyeRest,
      LogActionTypeCodeEnum.Create,
      now.difference(eyeRestCreated),
    );

    await log(
      medication,
      LogActionTypeCodeEnum.Dismiss,
      const Duration(hours: 16, minutes: 52),
      sinceLastDismissal: const Duration(hours: 8, minutes: 3),
    );
    await log(
      hydrate,
      LogActionTypeCodeEnum.Dismiss,
      const Duration(hours: 2, minutes: 21),
      sinceLastDismissal: const Duration(hours: 1, minutes: 2),
    );
    await log(
      stretch,
      LogActionTypeCodeEnum.Dismiss,
      const Duration(hours: 1, minutes: 48),
      sinceLastDismissal: const Duration(hours: 1, minutes: 32),
    );
    await log(
      hydrate,
      LogActionTypeCodeEnum.Ring,
      const Duration(hours: 1, minutes: 23),
    );
    await log(
      hydrate,
      LogActionTypeCodeEnum.AutoSnooze,
      const Duration(hours: 1, minutes: 18),
    );
    await log(
      eyeRest,
      LogActionTypeCodeEnum.Skip,
      const Duration(hours: 1, minutes: 12),
    );
    await log(medication, LogActionTypeCodeEnum.Ring, const Duration(hours: 1));
    await log(
      medication,
      LogActionTypeCodeEnum.Snooze,
      const Duration(minutes: 59),
    );
    await log(
      medication,
      LogActionTypeCodeEnum.Dismiss,
      const Duration(minutes: 50),
      sinceLastDismissal: const Duration(hours: 8, minutes: 6),
    );
    await log(
      hydrate,
      LogActionTypeCodeEnum.Ring,
      const Duration(minutes: 27, seconds: 42),
    );
    await log(
      hydrate,
      LogActionTypeCodeEnum.Snooze,
      const Duration(minutes: 22, seconds: 42),
    );
    await log(stretch, LogActionTypeCodeEnum.Mute, const Duration(minutes: 26));
    await log(
      stretch,
      LogActionTypeCodeEnum.Dismiss,
      const Duration(minutes: 24),
      sinceLastDismissal: const Duration(hours: 1, minutes: 30),
      wasMuted: true,
    );
    await log(
      hydrate,
      LogActionTypeCodeEnum.Dismiss,
      const Duration(minutes: 17, seconds: 42),
      sinceLastDismissal: const Duration(hours: 1, minutes: 5, seconds: 21),
    );
    await log(
      posture,
      LogActionTypeCodeEnum.Create,
      now.difference(postureCreated),
    );
    await log(
      vitamins,
      LogActionTypeCodeEnum.Create,
      now.difference(vitaminsCreated),
    );
    await log(
      vitamins,
      LogActionTypeCodeEnum.Dismiss,
      const Duration(minutes: 29),
      sinceLastDismissal: const Duration(minutes: 31),
    );
    await log(
      posture,
      LogActionTypeCodeEnum.Dismiss,
      const Duration(minutes: 26, seconds: 30),
      sinceLastDismissal: const Duration(minutes: 47, seconds: 10),
    );
    await log(eyeRest, LogActionTypeCodeEnum.Pause, const Duration(minutes: 5));

    return _DemoRoutineIds(
      medication: medication,
      hydrate: hydrate,
      stretch: stretch,
      eyeRest: eyeRest,
    );
  });
}
