import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/routine_ui_phase.dart';

/// Provides the singleton [RA_Database] instance.
/// Overridden in main() with the concrete, path-resolved instance.
final RA_DatabaseProvider = Provider<RA_Database>((ref) {
  throw UnimplementedError(
    'RA_DatabaseProvider must be overridden with a concrete RA_Database '
    'instance in the root ProviderScope.',
  );
});

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

/// Watches the [RoutineStateModel] for a given routine ID.
final ActiveRoutineStateProvider = StreamProvider.autoDispose
    .family<RoutineStateModel?, int>((ref, routineId) {
      final db = ref.watch(RA_DatabaseProvider);
      return db.watchRoutineState(routineId);
    });

/// Derives card UI phase from [ActiveRoutineStateProvider], selecting only
/// [IsRinging], [NextTriggerTime], and [PausedAt] so snooze count and other
/// fields do not rebuild chrome or status widgets.
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
