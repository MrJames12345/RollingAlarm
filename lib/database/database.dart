import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:rolling_alarm/database/tables/log_entries.dart';
import 'package:rolling_alarm/database/tables/routine_states.dart';
import 'package:rolling_alarm/database/tables/routines.dart';
import 'package:rolling_alarm/enums/log_action_type_code.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Routines, RoutineStates, LogEntries])
class RA_Database extends _$RA_Database {
  RA_Database() : super(_openConnection());

  /// Named constructor for testing with an in-memory database.
  RA_Database.forTesting(super.e);

  @override
  int get schemaVersion => 16;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        // Collapse any historical duplicate state rows before the unique index.
        await customStatement('''
          DELETE FROM routine_states
          WHERE id NOT IN (
            SELECT MIN(id) FROM routine_states GROUP BY routine_id
          );
        ''');
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS '
          'idx_routine_states_routine_id ON routine_states (routine_id);',
        );
      }
      if (from < 3) {
        await customStatement(
          'ALTER TABLE routines ADD COLUMN interval_seconds INTEGER NOT NULL '
          'DEFAULT 0;',
        );
      }
      if (from < 4) {
        // Drop MaxSnoozes and AutoSnoozeOnIgnore; ignore always auto-snoozes.
        // Keep hours/minutes/seconds columns so from < 5 can still consolidate.
        await customStatement('''
          CREATE TABLE routines_v4 (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL CHECK(length(name) >= 1 AND length(name) <= 255),
            snooze_minutes INTEGER NOT NULL DEFAULT 5,
            interval_hours INTEGER NOT NULL,
            interval_minutes INTEGER NOT NULL,
            interval_seconds INTEGER NOT NULL DEFAULT 0,
            drift_compensation_type_code INTEGER NOT NULL,
            show_preview INTEGER NOT NULL DEFAULT 1 CHECK(show_preview IN (0, 1)),
            audio_uri TEXT NULL,
            is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
            created_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
            modified_at INTEGER NULL,
            deleted INTEGER NOT NULL DEFAULT 0 CHECK(deleted IN (0, 1))
          );
        ''');
        await customStatement('''
          INSERT INTO routines_v4 (
            id, name, snooze_minutes, interval_hours, interval_minutes,
            interval_seconds, drift_compensation_type_code, show_preview,
            audio_uri, is_active, created_at, modified_at, deleted
          )
          SELECT
            id, name, snooze_minutes, interval_hours, interval_minutes,
            COALESCE(interval_seconds, 0), drift_compensation_type_code,
            show_preview, audio_uri, is_active, created_at, modified_at, deleted
          FROM routines;
        ''');
        await customStatement('DROP TABLE routines;');
        await customStatement('ALTER TABLE routines_v4 RENAME TO routines;');
      }
      if (from < 5) {
        // Fold hours/minutes/remainder-seconds into a single total seconds value.
        await customStatement('''
          UPDATE routines SET interval_seconds =
            (interval_hours * 3600) + (interval_minutes * 60) + interval_seconds;
        ''');
        await m.alterTable(TableMigration(routines));
      }
      if (from < 6) {
        await m.addColumn(routines, routines.MaxTimesPerDay);
        await m.addColumn(routineStates, routineStates.TimesRingToday);
        await m.addColumn(routineStates, routineStates.TimesRingDay);
      }
      if (from < 7) {
        await m.addColumn(routines, routines.DayStartSeconds);
      }
      if (from < 8) {
        await m.addColumn(routines, routines.MaxTimesPerDayEnabled);
        await customStatement(
          'UPDATE routines SET max_times_per_day_enabled = 1 '
          'WHERE max_times_per_day > 0',
        );
      }
      if (from < 9) {
        await customStatement(
          'ALTER TABLE routines ADD COLUMN snooze_seconds INTEGER NOT NULL DEFAULT 300;',
        );
        await customStatement(
          'UPDATE routines SET snooze_seconds = COALESCE(snooze_minutes, 5) * 60;',
        );
        await m.alterTable(TableMigration(routines));
      }
      if (from < 10) {
        await m.addColumn(routines, routines.Vibrate);
      }
      if (from < 11) {
        await m.addColumn(routines, routines.Volume);
      }
      if (from < 12) {
        await m.addColumn(routines, routines.FadeIn);
      }
      if (from < 13) {
        await m.addColumn(routineStates, routineStates.PausedAt);
      }
      if (from < 14) {
        await m.addColumn(routineStates, routineStates.MutedAt);
      }
      if (from < 15) {
        await m.addColumn(routines, routines.EnabledWeekdays);
      }
      if (from < 16) {
        await m.addColumn(logEntries, logEntries.WasMuted);
      }
    },
  );

  // --------------------------------------------------------------------- //
  // Routine queries
  // --------------------------------------------------------------------- //

  Stream<List<RoutineModel>> watchAllRoutines() {
    return (select(routines)
          ..where((r) => r.Deleted.equals(false))
          ..orderBy([(r) => OrderingTerm.asc(r.CreatedAt)]))
        .watch();
  }

  /// Maps each routine id to its name, including soft deleted rows, so global
  /// log history can still label events after a routine is removed.
  Stream<Map<int, String>> watchRoutineNamesById() {
    return select(
      routines,
    ).watch().map((rows) => {for (final r in rows) r.Id: r.Name});
  }

  /// Soft-deleted flag per routine id (includes live and deleted rows).
  Stream<Map<int, bool>> watchRoutineDeletedById() {
    return select(
      routines,
    ).watch().map((rows) => {for (final r in rows) r.Id: r.Deleted});
  }

  Future<RoutineModel> getRoutineById(int id) {
    return (select(routines)..where((r) => r.Id.equals(id))).getSingle();
  }

  /// Active, non-deleted routines used to re-arm AlarmManager after boot,
  /// force-stop, or any other loss of OS timers.
  Future<List<RoutineModel>> getActiveRoutines() {
    return (select(routines)
          ..where((r) => r.Deleted.equals(false))
          ..where((r) => r.IsActive.equals(true)))
        .get();
  }

  Future<int> insertRoutine(RoutinesCompanion routine) {
    return into(routines).insert(routine);
  }

  /// Inserts a routine and its initial state row in one transaction so a
  /// crash cannot leave an active routine without [RoutineStates] (alarm
  /// scheduling would then have nothing to CAS against).
  ///
  /// When [activityLog] is set (default [LogActionTypeCodeEnum.Create]),
  /// writes a matching history row in the same transaction.
  Future<int> insertRoutineWithInitialState({
    required RoutinesCompanion routine,
    required DateTime nextTriggerTime,
    LogActionTypeCodeEnum? activityLog = LogActionTypeCodeEnum.Create,
  }) {
    return transaction(() async {
      final routineId = await insertRoutine(routine);
      await insertRoutineState(
        RoutineStatesCompanion(
          RoutineId: Value(routineId),
          NextTriggerTime: Value(nextTriggerTime),
        ),
      );
      if (activityLog != null) {
        await insertActivityLog(routineId: routineId, action: activityLog);
      }
      return routineId;
    });
  }

  /// Partial update so edit forms can omit unchanged columns such as
  /// [AudioUri], [IsActive], and [CreatedAt] without wiping them.
  Future<int> updateRoutine(RoutinesCompanion routine) {
    final id = routine.Id.present ? routine.Id.value : null;
    if (id == null) {
      throw ArgumentError('updateRoutine requires RoutinesCompanion.Id');
    }
    return (update(routines)..where((r) => r.Id.equals(id))).write(
      routine.copyWith(ModifiedAt: Value(DateTime.now())),
    );
  }

  /// Soft deletes the routine and clears its live state so ringing /
  /// countdown watches cannot resurrect a deleted alarm cycle.
  ///
  /// Routines are never hard deleted: only the [Deleted] flag is set so
  /// history can still resolve names and [recoverRoutine] can restore them.
  ///
  /// Both writes run in one transaction so a kill mid-delete cannot leave a
  /// deleted routine with a still-live ringing state (or the reverse).
  /// Also records a [LogActionTypeCodeEnum.Delete] history entry.
  Future<void> softDeleteRoutine(int id) async {
    final now = DateTime.now();
    await transaction(() async {
      await insertActivityLog(
        routineId: id,
        action: LogActionTypeCodeEnum.Delete,
        timestamp: now,
      );
      await (update(routines)..where((r) => r.Id.equals(id))).write(
        RoutinesCompanion(Deleted: const Value(true), ModifiedAt: Value(now)),
      );
      await (update(routineStates)..where((s) => s.RoutineId.equals(id))).write(
        RoutineStatesCompanion(
          Deleted: const Value(true),
          IsRinging: const Value(false),
          NextTriggerTime: const Value(null),
          PausedAt: const Value(null),
          MutedAt: const Value(null),
          ModifiedAt: Value(now),
        ),
      );
    });
  }

  /// Clears soft-delete on the routine and its state, then sets
  /// [NextTriggerTime]. Does not schedule the OS alarm (caller does).
  ///
  /// No-ops when the routine is missing or not soft-deleted.
  /// Records a [LogActionTypeCodeEnum.Recover] history entry on success.
  Future<bool> recoverRoutine({
    required int id,
    required DateTime nextTriggerTime,
  }) async {
    final routine = await getRoutineById(id);
    if (!routine.Deleted) return false;

    final now = DateTime.now();
    await transaction(() async {
      await (update(routines)..where((r) => r.Id.equals(id))).write(
        RoutinesCompanion(
          Deleted: const Value(false),
          IsActive: const Value(true),
          ModifiedAt: Value(now),
        ),
      );
      // Soft-deleted state rows are filtered out of [updateRoutineState];
      // write the live row directly so Deleted can flip back to false.
      await (update(routineStates)..where((s) => s.RoutineId.equals(id))).write(
        RoutineStatesCompanion(
          Deleted: const Value(false),
          IsRinging: const Value(false),
          PausedAt: const Value(null),
          MutedAt: const Value(null),
          NextTriggerTime: Value(nextTriggerTime),
          CurrentSnoozeCount: const Value(0),
          ModifiedAt: Value(now),
        ),
      );
      await insertActivityLog(
        routineId: id,
        action: LogActionTypeCodeEnum.Recover,
        timestamp: now,
      );
    });
    return true;
  }

  // --------------------------------------------------------------------- //
  // RoutineState queries
  // --------------------------------------------------------------------- //

  Stream<RoutineStateModel?> watchRoutineState(int routineId) {
    return (select(routineStates)
          ..where((s) => s.RoutineId.equals(routineId))
          ..where((s) => s.Deleted.equals(false)))
        .watchSingleOrNull();
  }

  Stream<List<RoutineStateModel>> watchRingingRoutineStates() {
    return (select(routineStates)
          ..where((s) => s.IsRinging.equals(true))
          ..where((s) => s.Deleted.equals(false)))
        .watch();
  }

  Future<List<RoutineStateModel>> getRingingRoutineStates() {
    return (select(routineStates)
          ..where((s) => s.IsRinging.equals(true))
          ..where((s) => s.Deleted.equals(false)))
        .get();
  }

  Future<RoutineStateModel?> getRoutineState(int routineId) {
    return (select(routineStates)
          ..where((s) => s.RoutineId.equals(routineId))
          ..where((s) => s.Deleted.equals(false)))
        .getSingleOrNull();
  }

  Future<int> insertRoutineState(RoutineStatesCompanion state) {
    return into(routineStates).insert(state);
  }

  /// Ensures a live (non-deleted) state row exists for [routineId] without
  /// racing duplicate inserts across UI and alarm isolates (unique [RoutineId]).
  ///
  /// Soft-deleted rows are left alone; callers see `null` and must not treat
  /// that as a cue to insert again (unique key still occupied).
  Future<RoutineStateModel?> ensureRoutineState(int routineId) async {
    final existing = await getRoutineState(routineId);
    if (existing != null) return existing;
    await into(routineStates).insert(
      RoutineStatesCompanion(RoutineId: Value(routineId)),
      mode: InsertMode.insertOrIgnore,
    );
    return getRoutineState(routineId);
  }

  /// Updates the live state row for [routineId].
  ///
  /// When [requireIsRinging] is non-null, the write is a compare-and-swap: it
  /// only matches rows whose [RoutineStates.IsRinging] equals that value.
  /// When [matchNextTriggerTime] is true, the write also requires
  /// [NextTriggerTime] to equal [nextTriggerTimeToMatch] (including null), so
  /// concurrent idle Skip writers cannot both commit.
  /// Returns `0` when the row is missing, soft-deleted, or lost a cross-isolate
  /// race (another writer already flipped [IsRinging] / [NextTriggerTime]).
  Future<int> updateRoutineState(
    int routineId,
    RoutineStatesCompanion state, {
    bool? requireIsRinging,
    bool matchNextTriggerTime = false,
    DateTime? nextTriggerTimeToMatch,
  }) {
    final query = update(routineStates)
      ..where((s) => s.RoutineId.equals(routineId))
      ..where((s) => s.Deleted.equals(false));
    if (requireIsRinging != null) {
      query.where((s) => s.IsRinging.equals(requireIsRinging));
    }
    if (matchNextTriggerTime) {
      if (nextTriggerTimeToMatch == null) {
        query.where((s) => s.NextTriggerTime.isNull());
      } else {
        query.where((s) => s.NextTriggerTime.equals(nextTriggerTimeToMatch));
      }
    }
    return query.write(state.copyWith(ModifiedAt: Value(DateTime.now())));
  }

  // --------------------------------------------------------------------- //
  // LogEntry queries
  // --------------------------------------------------------------------- //

  Stream<List<LogEntryModel>> watchLogEntries({int? routineId}) {
    final query = select(logEntries)
      ..where((l) => l.Deleted.equals(false))
      ..orderBy([(l) => OrderingTerm.desc(l.Timestamp)]);
    if (routineId != null) {
      query.where((l) => l.RoutineId.equals(routineId));
    }
    return query.watch();
  }

  Future<int> insertLogEntry(LogEntriesCompanion entry) {
    return into(logEntries).insert(entry);
  }

  /// Convenience writer for routine lifecycle / activity history rows.
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

  Future<List<LogEntryModel>> getAllLogEntries() {
    return (select(logEntries)
          ..where((l) => l.Deleted.equals(false))
          ..orderBy([(l) => OrderingTerm.desc(l.Timestamp)]))
        .get();
  }

  /// Count of [LogActionTypeCodeEnum.Dismiss] events for [routineId] at or
  /// after [since] (typically the routine's current day-period start).
  Future<int> countDismissalsSince({
    required int routineId,
    required DateTime since,
  }) async {
    final dismissCode = LogActionTypeCodeEnum.Dismiss.index;
    final rows =
        await (select(logEntries)
              ..where((l) => l.Deleted.equals(false))
              ..where((l) => l.RoutineId.equals(routineId))
              ..where((l) => l.LogActionTypeCode.equals(dismissCode))
              ..where((l) => l.Timestamp.isBiggerOrEqualValue(since)))
            .get();
    return rows.length;
  }

  // --------------------------------------------------------------------- //
  // Connection
  // --------------------------------------------------------------------- //

  /// UI / main isolate opener: SQLite work runs on Drift's worker isolate so
  /// frames are not blocked. Background alarm/widget isolates must use
  /// [openForIsolate] instead (already off the UI thread; nesting another
  /// createInBackground hop is unnecessary and harder to close cleanly).
  static QueryExecutor _openConnection() {
    return NativeDatabase.createInBackground(
      _getDatabaseFile(),
      setup: _applyConcurrencyPragmas,
    );
  }

  static void _applyConcurrencyPragmas(dynamic db) {
    // busy_timeout must be armed BEFORE journal_mode=WAL: switching to WAL
    // briefly needs an exclusive lock for -shm setup, and concurrent cold opens
    // (UI createInBackground + alarm openForIsolate) fail instantly if the
    // busy handler is not registered yet.
    db.execute('PRAGMA busy_timeout = 5000;');
    db.execute('PRAGMA journal_mode = WAL;');
    // NORMAL is the usual pairing with WAL: durable enough for alarm state,
    // cheaper than FULL under concurrent short writers.
    db.execute('PRAGMA synchronous = NORMAL;');
  }

  static String? _resolvedDbPath;

  static void setResolvedDatabasePath(String path) {
    _resolvedDbPath = path;
  }

  static File _getDatabaseFile() {
    final path = _resolvedDbPath;
    if (path == null) {
      throw StateError(
        'RA_Database path is unresolved. Call resolveDatabasePath() '
        '(or setResolvedDatabasePath) on the main isolate before opening.',
      );
    }
    return File(path);
  }

  /// Opens a short lived sync connection for a background isolate that cannot
  /// use path_provider. Callers must [close] in a finally block.
  static RA_Database openForIsolate(String dbPath) {
    _resolvedDbPath = dbPath;
    return RA_Database.forTesting(
      NativeDatabase(File(dbPath), setup: _applyConcurrencyPragmas),
    );
  }

  /// Resolves the database file path using path_provider.
  /// Must be called from the main isolate before first use.
  static Future<String> resolveDatabasePath() async {
    final appDir = await getApplicationDocumentsDirectory();
    _resolvedDbPath = p.join(appDir.path, 'rolling_alarm.db');
    return _resolvedDbPath!;
  }
}
