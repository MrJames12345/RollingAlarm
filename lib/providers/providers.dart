import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/alarm_side_button_action.dart';
import 'package:rolling_alarm/enums/alarm_snooze_dismiss_layout.dart';
import 'package:rolling_alarm/enums/app_theme_mode.dart';
import 'package:rolling_alarm/enums/routine_swipe_action.dart';
import 'package:rolling_alarm/enums/routine_ui_phase.dart';
import 'package:rolling_alarm/services/settings.dart';
import 'package:rolling_alarm/styles.dart';

/// Provides the singleton [RA_Database] instance.
/// Overridden in main() with the concrete, path-resolved instance.
final RA_DatabaseProvider = Provider<RA_Database>((ref) {
  throw UnimplementedError(
    'RA_DatabaseProvider must be overridden with a concrete RA_Database '
    'instance in the root ProviderScope.',
  );
});

/// App-wide snooze/dismiss control layout on the alarm ring screen.
final AlarmSnoozeDismissLayoutProvider =
    AsyncNotifierProvider<
      AlarmSnoozeDismissLayoutNotifier,
      AlarmSnoozeDismissLayoutEnum
    >(AlarmSnoozeDismissLayoutNotifier.new);

class AlarmSnoozeDismissLayoutNotifier
    extends AsyncNotifier<AlarmSnoozeDismissLayoutEnum> {
  @override
  Future<AlarmSnoozeDismissLayoutEnum> build() {
    return RA_SettingsService.getAlarmSnoozeDismissLayout();
  }

  Future<void> setLayout(AlarmSnoozeDismissLayoutEnum layout) async {
    state = AsyncData(layout);
    await RA_SettingsService.setAlarmSnoozeDismissLayout(layout);
  }
}

/// App chrome theme (light or dark), persisted in SharedPreferences.
final AppThemeModeProvider =
    AsyncNotifierProvider<AppThemeModeNotifier, AppThemeModeEnum>(
      AppThemeModeNotifier.new,
    );

class AppThemeModeNotifier extends AsyncNotifier<AppThemeModeEnum> {
  @override
  Future<AppThemeModeEnum> build() async {
    final mode = await RA_SettingsService.getThemeMode();
    RA_ColourStyles.apply(mode);
    return mode;
  }

  Future<void> setMode(AppThemeModeEnum mode) async {
    RA_ColourStyles.apply(mode);
    state = AsyncData(mode);
    await RA_SettingsService.setThemeMode(mode);
  }
}

/// Hardware side button actions while an alarm is ringing.
final AlarmSideButtonsProvider =
    AsyncNotifierProvider<AlarmSideButtonsNotifier, AlarmSideButtonsSettings>(
      AlarmSideButtonsNotifier.new,
    );

class AlarmSideButtonsNotifier extends AsyncNotifier<AlarmSideButtonsSettings> {
  @override
  Future<AlarmSideButtonsSettings> build() {
    return RA_SettingsService.getSideButtons();
  }

  Future<void> setButtonAction({
    required AlarmSideButtonEnum button,
    required AlarmSideButtonActionEnum action,
  }) async {
    final current = state.valueOrNull ?? const AlarmSideButtonsSettings();
    final next = current.copyWithButton(button: button, action: action);
    state = AsyncData(next);
    await RA_SettingsService.setSideButtonAction(
      button: button,
      action: action,
    );
  }
}

/// Left/right swipe actions on home routine cards.
final RoutineSwipeActionsProvider =
    AsyncNotifierProvider<
      RoutineSwipeActionsNotifier,
      RoutineSwipeActionsSettings
    >(RoutineSwipeActionsNotifier.new);

class RoutineSwipeActionsNotifier
    extends AsyncNotifier<RoutineSwipeActionsSettings> {
  @override
  Future<RoutineSwipeActionsSettings> build() {
    return RA_SettingsService.getSwipeActions();
  }

  Future<void> setDirectionAction({
    required RoutineSwipeDirectionEnum direction,
    required RoutineSwipeActionEnum action,
  }) async {
    final current = state.valueOrNull ?? const RoutineSwipeActionsSettings();
    final next = current.copyWithDirection(
      direction: direction,
      action: action,
    );
    state = AsyncData(next);
    await RA_SettingsService.setSwipeAction(
      direction: direction,
      action: action,
    );
  }
}

/// Watches all non-deleted routines as a reactive stream.
///
/// [autoDispose] cancels the Riverpod subscription on leave, which cancels
/// Drift's query stream (no keepAlive, no manual [ref.onDispose] needed).
final RoutineListProvider = StreamProvider.autoDispose<List<RoutineModel>>((
  ref,
) {
  final db = ref.watch(RA_DatabaseProvider);
  return db.watchAllRoutines();
});

/// Maps routine ids to names for all routines, including soft deleted ones.
final RoutineNamesByIdProvider =
    StreamProvider.autoDispose<Map<int, String>>((ref) {
      final db = ref.watch(RA_DatabaseProvider);
      return db.watchRoutineNamesById();
    });

/// Soft-deleted flag per routine id (includes live and deleted rows).
final RoutineDeletedByIdProvider =
    StreamProvider.autoDispose<Map<int, bool>>((ref) {
      final db = ref.watch(RA_DatabaseProvider);
      return db.watchRoutineDeletedById();
    });

/// Watches the [RoutineStateModel] for a given routine ID.
final ActiveRoutineStateProvider = StreamProvider.autoDispose
    .family<RoutineStateModel?, int>((ref, routineId) {
      final db = ref.watch(RA_DatabaseProvider);
      return db.watchRoutineState(routineId);
    });

/// Derives card UI phase from [ActiveRoutineStateProvider], selecting only
/// [IsRinging], [NextTriggerTime], [PausedAt], and [MutedAt] so snooze count
/// and other fields do not rebuild chrome or status widgets.
final RoutineUiSnapshotProvider = Provider.autoDispose
    .family<RA_RoutineUiSnapshot, int>((ref, routineId) {
      return ref.watch(
        ActiveRoutineStateProvider(routineId).select(_snapshotFromAsync),
      );
    });

RA_RoutineUiSnapshot _snapshotFromAsync(AsyncValue<RoutineStateModel?> async) {
  return async.when(
    data: (s) {
      if (s == null) return const RA_RoutineUiSnapshot.notScheduled();
      if (s.PausedAt != null) {
        return RA_RoutineUiSnapshot.paused(
          pausedAt: s.PausedAt!,
          nextTriggerTime: s.NextTriggerTime,
        );
      }
      if (s.MutedAt != null && s.NextTriggerTime != null) {
        return RA_RoutineUiSnapshot.muted(s.NextTriggerTime!);
      }
      if (s.MutedAt != null) {
        return const RA_RoutineUiSnapshot.idle();
      }
      if (s.IsRinging) return const RA_RoutineUiSnapshot.ringing();
      if (s.NextTriggerTime != null) {
        return RA_RoutineUiSnapshot.countingDown(s.NextTriggerTime!);
      }
      return const RA_RoutineUiSnapshot.idle();
    },
    loading: () => const RA_RoutineUiSnapshot.loading(),
    error: (_, _) => const RA_RoutineUiSnapshot.error(),
  );
}

/// Watches all currently ringing routine states.
final RingingRoutineStatesProvider =
    StreamProvider.autoDispose<List<RoutineStateModel>>((ref) {
      final db = ref.watch(RA_DatabaseProvider);
      return db.watchRingingRoutineStates();
    });

/// Watches all log entries, optionally filtered by routine ID.
final LogEntriesProvider = StreamProvider.autoDispose
    .family<List<LogEntryModel>, int?>((ref, routineId) {
      final db = ref.watch(RA_DatabaseProvider);
      return db.watchLogEntries(routineId: routineId);
    });

/// Shared wall-clock second stream so every countdown flips on the same tick.
///
/// Aligns to real-world second boundaries (e.g. 12:00:01.000) instead of each
/// card's mount time, which previously left timers 300 to 500ms out of phase.
final WallClockSecondProvider = StreamProvider.autoDispose<DateTime>((ref) {
  return _wallClockSecondStream();
});

/// Remaining time until [nextTriggerTime], refreshed on each wall-clock second.
///
/// Only [RA_Countdown] should watch this; parent cards watch phase snapshots.
final CountdownProvider = Provider.autoDispose.family<Duration, DateTime>((
  ref,
  nextTriggerTime,
) {
  final tick = ref.watch(WallClockSecondProvider).valueOrNull;
  final now = tick ?? DateTime.now();
  return nextTriggerTime.difference(now);
});

/// Yields [DateTime.now] immediately, then again at every wall-clock second.
///
/// Each wait is recomputed from the clock so timer drift cannot accumulate.
Stream<DateTime> _wallClockSecondStream() async* {
  while (true) {
    final now = DateTime.now();
    yield now;
    final nextSecond = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second + 1,
    );
    var delay = nextSecond.difference(DateTime.now());
    if (delay <= Duration.zero) {
      delay = const Duration(milliseconds: 1);
    }
    await Future<void>.delayed(delay);
  }
}
