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
/// [IsRinging] and [NextTriggerTime] so snooze count and other fields do not
/// rebuild chrome or status widgets.
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

/// Per-second countdown stream for a given [NextTriggerTime].
/// Ticks once per second and emits the remaining [Duration].
/// Only [RA_Countdown] should watch this; parent cards watch phase snapshots.
final CountdownProvider = StreamProvider.autoDispose.family<Duration, DateTime>(
  (ref, nextTriggerTime) {
    return _countdownStream(nextTriggerTime);
  },
);

/// Emits the remaining time immediately so the countdown never renders a
/// placeholder for the first second, then once per second afterwards.
///
/// Cancellation of the Riverpod subscription cancels this async* loop, which
/// cancels the inner [Stream.periodic] so no Timer survives navigation away.
Stream<Duration> _countdownStream(DateTime nextTriggerTime) async* {
  yield nextTriggerTime.difference(DateTime.now());
  await for (final _ in Stream.periodic(const Duration(seconds: 1))) {
    yield nextTriggerTime.difference(DateTime.now());
  }
}
