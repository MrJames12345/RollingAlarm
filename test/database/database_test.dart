import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';
import 'package:rolling_alarm/enums/log_action_type_code.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('RA_Database Tests', () {
    late RA_Database db;

    setUp(() {
      db = RA_Database.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('RoutineState transitions work correctly', () async {
      // 1. Insert a routine
      final routineId = await db.insertRoutine(
        RoutinesCompanion(
          Name: const Value('Morning Alarm'),
          IntervalSeconds: const Value(28800),
          DriftCompensationTypeCode: Value(
            DriftCompensationTypeCodeEnum.ActualDismissal.index,
          ),
        ),
      );

      // 2. Insert initial state (idle)
      await db.insertRoutineState(
        RoutineStatesCompanion(
          RoutineId: Value(routineId),
          IsRinging: const Value(false),
          CurrentSnoozeCount: const Value(0),
        ),
      );

      var state = await db.getRoutineState(routineId);
      expect(state, isNotNull);
      expect(state!.IsRinging, isFalse);
      expect(state.CurrentSnoozeCount, equals(0));

      // 3. Transition to ringing
      final triggerTime = DateTime(2026, 1, 1, 7, 0, 0);
      await db.updateRoutineState(
        routineId,
        RoutineStatesCompanion(
          IsRinging: const Value(true),
          NextTriggerTime: Value(triggerTime),
          InitialRingTime: Value(triggerTime),
        ),
      );

      state = await db.getRoutineState(routineId);
      expect(state!.IsRinging, isTrue);
      expect(state.NextTriggerTime, equals(triggerTime));

      // 4. Transition to snoozed (increment count, not ringing)
      final snoozeTime = triggerTime.add(const Duration(minutes: 9));
      await db.updateRoutineState(
        routineId,
        RoutineStatesCompanion(
          IsRinging: const Value(false),
          CurrentSnoozeCount: const Value(1),
          NextTriggerTime: Value(snoozeTime),
        ),
      );

      state = await db.getRoutineState(routineId);
      expect(state!.IsRinging, isFalse);
      expect(state.CurrentSnoozeCount, equals(1));
      expect(state.NextTriggerTime, equals(snoozeTime));
    });

    test('LogEntry writes with correct TimeSinceLastDismissal', () async {
      final routineId = await db.insertRoutine(
        RoutinesCompanion(
          Name: const Value('Test Routine'),
          IntervalSeconds: const Value(16200),
          DriftCompensationTypeCode: Value(
            DriftCompensationTypeCodeEnum.InitialRing.index,
          ),
        ),
      );

      // First dismissal (no previous dismissal, so null or 0)
      final firstDismissalTime = DateTime(2026, 1, 1, 8, 0, 0);
      await db.insertLogEntry(
        LogEntriesCompanion(
          RoutineId: Value(routineId),
          LogActionTypeCode: Value(LogActionTypeCodeEnum.Dismiss.index),
          Timestamp: Value(firstDismissalTime),
          TimeSinceLastDismissalSeconds: const Value(null),
        ),
      );

      // Second dismissal 4 hours and 30 minutes later (16200 seconds)
      final secondDismissalTime = firstDismissalTime.add(
        const Duration(hours: 4, minutes: 30),
      );
      final secondsDiff = secondDismissalTime
          .difference(firstDismissalTime)
          .inSeconds;

      await db.insertLogEntry(
        LogEntriesCompanion(
          RoutineId: Value(routineId),
          LogActionTypeCode: Value(LogActionTypeCodeEnum.Dismiss.index),
          Timestamp: Value(secondDismissalTime),
          TimeSinceLastDismissalSeconds: Value(secondsDiff),
        ),
      );

      final logs = await db.getAllLogEntries();
      expect(logs.length, equals(2));

      // Most recent log is first due to desc ordering
      expect(logs[0].Timestamp, equals(secondDismissalTime));
      expect(logs[0].TimeSinceLastDismissalSeconds, equals(16200));
      expect(logs[1].Timestamp, equals(firstDismissalTime));
      expect(logs[1].TimeSinceLastDismissalSeconds, isNull);
    });

    test(
      'Second connection to the same file observes first connection writes',
      () async {
        // Create a temporary file for the SQLite database
        final tempDir = await Directory.systemTemp.createTemp('ra_db_test');
        final dbPath = p.join(tempDir.path, 'shared_test.db');

        try {
          // Connection 1 (simulating Main Isolate)
          final db1 = RA_Database.openForIsolate(dbPath);
          final routineId = await db1.insertRoutine(
            RoutinesCompanion(
              Name: const Value('Shared Routine'),
              IntervalSeconds: const Value(7200),
              DriftCompensationTypeCode: Value(
                DriftCompensationTypeCodeEnum.ActualDismissal.index,
              ),
            ),
          );
          await db1.close();

          // Connection 2 (simulating Background Alarm Isolate)
          final db2 = RA_Database.openForIsolate(dbPath);
          final routine = await db2.getRoutineById(routineId);
          expect(routine.Name, equals('Shared Routine'));
          expect(routine.IntervalSeconds, equals(2 * 3600));

          // Background isolate updates state
          await db2.insertRoutineState(
            RoutineStatesCompanion(
              RoutineId: Value(routineId),
              IsRinging: const Value(true),
              CurrentSnoozeCount: const Value(0),
            ),
          );
          await db2.close();

          // Connection 3 (main isolate re-reading after alarm fired)
          final db3 = RA_Database.openForIsolate(dbPath);
          final state = await db3.getRoutineState(routineId);
          expect(state, isNotNull);
          expect(state!.IsRinging, isTrue);
          await db3.close();
        } finally {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        }
      },
    );

    test(
      'updateRoutine preserves omitted columns such as AudioUri and CreatedAt',
      () async {
        final routineId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Preserve Me'),
            IntervalSeconds: const Value(14400),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.InitialRing.index,
            ),
            AudioUri: const Value('file:///custom.mp3'),
            IsActive: const Value(true),
          ),
        );

        final before = await db.getRoutineById(routineId);
        await db.updateRoutine(
          RoutinesCompanion(
            Id: Value(routineId),
            Name: const Value('Renamed'),
            IntervalSeconds: const Value(22500),
            SnoozeSeconds: const Value(540),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            ShowPreview: const Value(true),
          ),
        );

        final after = await db.getRoutineById(routineId);
        expect(after.Name, equals('Renamed'));
        expect(after.IntervalSeconds, equals(6 * 3600 + 15 * 60));
        expect(after.SnoozeSeconds, equals(540));
        expect(after.AudioUri, equals('file:///custom.mp3'));
        expect(after.IsActive, isTrue);
        expect(after.Vibrate, isTrue);
        expect(after.Volume, equals(50));
        expect(after.FadeIn, isFalse);
        expect(after.CreatedAt, equals(before.CreatedAt));
        expect(after.Deleted, isFalse);
        expect(after.ModifiedAt, isNotNull);
      },
    );

    test(
      'softDeleteRoutine clears live state so ringing watches stop',
      () async {
        final routineId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Delete Me'),
            IntervalSeconds: const Value(7200),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
          ),
        );
        await db.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            IsRinging: const Value(true),
            NextTriggerTime: Value(DateTime(2026, 1, 1, 10, 0, 0)),
          ),
        );

        await db.softDeleteRoutine(routineId);

        final routines = await db.watchAllRoutines().first;
        expect(routines.where((r) => r.Id == routineId), isEmpty);

        final state = await db.getRoutineState(routineId);
        expect(state, isNull);

        final ringing = await db.getRingingRoutineStates();
        expect(ringing.where((s) => s.RoutineId == routineId), isEmpty);
      },
    );

    test('ensureRoutineState is idempotent under unique RoutineId', () async {
      final routineId = await db.insertRoutine(
        RoutinesCompanion(
          Name: const Value('Ensure State'),
          IntervalSeconds: const Value(3600),
          DriftCompensationTypeCode: Value(
            DriftCompensationTypeCodeEnum.ActualDismissal.index,
          ),
        ),
      );

      final first = await db.ensureRoutineState(routineId);
      final second = await db.ensureRoutineState(routineId);
      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first!.Id, equals(second!.Id));

      final all = await (db.select(
        db.routineStates,
      )..where((s) => s.RoutineId.equals(routineId))).get();
      expect(all.length, equals(1));
    });

    test(
      'updateRoutineState CAS returns 0 when IsRinging precondition fails',
      () async {
        final routineId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('CAS State'),
            IntervalSeconds: const Value(7200),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
          ),
        );
        await db.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            IsRinging: const Value(false),
          ),
        );

        final lost = await db.updateRoutineState(
          routineId,
          const RoutineStatesCompanion(
            IsRinging: Value(false),
            CurrentSnoozeCount: Value(1),
          ),
          requireIsRinging: true,
        );
        expect(lost, equals(0));

        await db.updateRoutineState(
          routineId,
          const RoutineStatesCompanion(IsRinging: Value(true)),
        );
        final won = await db.updateRoutineState(
          routineId,
          const RoutineStatesCompanion(
            IsRinging: Value(false),
            CurrentSnoozeCount: Value(1),
          ),
          requireIsRinging: true,
        );
        expect(won, equals(1));

        final state = await db.getRoutineState(routineId);
        expect(state!.IsRinging, isFalse);
        expect(state.CurrentSnoozeCount, equals(1));
      },
    );

    test('updateRoutineState ignores soft-deleted rows', () async {
      final routineId = await db.insertRoutine(
        RoutinesCompanion(
          Name: const Value('Soft Deleted State'),
          IntervalSeconds: const Value(7200),
          DriftCompensationTypeCode: Value(
            DriftCompensationTypeCodeEnum.ActualDismissal.index,
          ),
        ),
      );
      await db.insertRoutineState(
        RoutineStatesCompanion(
          RoutineId: Value(routineId),
          IsRinging: const Value(true),
        ),
      );
      await db.softDeleteRoutine(routineId);

      final rows = await db.updateRoutineState(
        routineId,
        const RoutineStatesCompanion(IsRinging: Value(true)),
      );
      expect(rows, equals(0));
      expect(await db.getRoutineState(routineId), isNull);
    });

    test(
      'updateRoutineState matchNextTriggerTime returns 0 after NextTriggerTime changes',
      () async {
        final routineId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Next Trigger Lock'),
            IntervalSeconds: const Value(7200),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
          ),
        );
        final next = DateTime(2026, 1, 1, 12, 0, 0);
        await db.insertRoutineState(
          RoutineStatesCompanion(
            RoutineId: Value(routineId),
            IsRinging: const Value(false),
            NextTriggerTime: Value(next),
          ),
        );

        final won = await db.updateRoutineState(
          routineId,
          RoutineStatesCompanion(
            NextTriggerTime: Value(next.add(const Duration(hours: 2))),
            CurrentSnoozeCount: const Value(0),
          ),
          matchNextTriggerTime: true,
          nextTriggerTimeToMatch: next,
        );
        expect(won, equals(1));

        final lost = await db.updateRoutineState(
          routineId,
          RoutineStatesCompanion(
            NextTriggerTime: Value(next.add(const Duration(hours: 4))),
          ),
          matchNextTriggerTime: true,
          nextTriggerTimeToMatch: next,
        );
        expect(lost, equals(0));
      },
    );

    test(
      'openForIsolate applies WAL, busy_timeout, and synchronous pragmas',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_pragma_');
        final dbPath = p.join(tempDir.path, 'pragma.db');
        try {
          final opened = RA_Database.openForIsolate(dbPath);
          final journal = await opened
              .customSelect('PRAGMA journal_mode;')
              .get();
          final busy = await opened.customSelect('PRAGMA busy_timeout;').get();
          final sync = await opened.customSelect('PRAGMA synchronous;').get();
          await opened.close();

          expect(
            journal.single.data.values.first.toString().toLowerCase(),
            equals('wal'),
          );
          expect(busy.single.data.values.first, equals(5000));
          // NORMAL == 1 in SQLite
          expect(sync.single.data.values.first, equals(1));
        } finally {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        }
      },
    );

    test('insertRoutineWithInitialState is atomic (routine + state)', () async {
      final routineId = await db.insertRoutineWithInitialState(
        routine: RoutinesCompanion(
          Name: const Value('Atomic Create'),
          IntervalSeconds: const Value(10800),
          DriftCompensationTypeCode: Value(
            DriftCompensationTypeCodeEnum.ActualDismissal.index,
          ),
        ),
        nextTriggerTime: DateTime(2026, 1, 1, 9, 0, 0),
      );

      final routine = await db.getRoutineById(routineId);
      expect(routine.Name, equals('Atomic Create'));
      final state = await db.getRoutineState(routineId);
      expect(state, isNotNull);
      expect(state!.NextTriggerTime, equals(DateTime(2026, 1, 1, 9, 0, 0)));
    });

    test('softDeleteRoutine clears routine and state together', () async {
      final routineId = await db.insertRoutineWithInitialState(
        routine: RoutinesCompanion(
          Name: const Value('Txn Delete'),
          IntervalSeconds: const Value(7200),
          DriftCompensationTypeCode: Value(
            DriftCompensationTypeCodeEnum.ActualDismissal.index,
          ),
        ),
        nextTriggerTime: DateTime(2026, 1, 1, 11, 0, 0),
      );
      await db.updateRoutineState(
        routineId,
        const RoutineStatesCompanion(IsRinging: Value(true)),
      );

      await db.softDeleteRoutine(routineId);

      final routine = await db.getRoutineById(routineId);
      expect(routine.Deleted, isTrue);
      expect(await db.getRoutineState(routineId), isNull);
      expect(await db.getRingingRoutineStates(), isEmpty);
    });

    test('recoverRoutine clears soft-delete and restores live state', () async {
      final routineId = await db.insertRoutineWithInitialState(
        routine: RoutinesCompanion(
          Name: const Value('Recover Me'),
          IntervalSeconds: const Value(3600),
          DriftCompensationTypeCode: Value(
            DriftCompensationTypeCodeEnum.ActualDismissal.index,
          ),
        ),
        nextTriggerTime: DateTime(2026, 1, 1, 12, 0, 0),
      );
      await db.softDeleteRoutine(routineId);

      final next = DateTime(2026, 1, 2, 8, 0, 0);
      final recovered = await db.recoverRoutine(
        id: routineId,
        nextTriggerTime: next,
      );
      expect(recovered, isTrue);

      final routine = await db.getRoutineById(routineId);
      expect(routine.Deleted, isFalse);
      expect(routine.IsActive, isTrue);
      final state = await db.getRoutineState(routineId);
      expect(state, isNotNull);
      expect(state!.Deleted, isFalse);
      expect(state.NextTriggerTime, equals(next));
      expect(state.IsRinging, isFalse);

      final logs = await db.getAllLogEntries();
      expect(
        logs.map((l) => l.LogActionTypeCode),
        containsAll([
          LogActionTypeCodeEnum.Create.index,
          LogActionTypeCodeEnum.Delete.index,
          LogActionTypeCodeEnum.Recover.index,
        ]),
      );

      // Already live: second recover is a no-op.
      expect(
        await db.recoverRoutine(id: routineId, nextTriggerTime: next),
        isFalse,
      );
    });

    test(
      'fresh v18 database is not grandfathered and countLiveRoutines excludes deleted',
      () async {
        expect(await db.isLegacyProGrandfathered(), isFalse);
        expect(await db.watchLegacyProGrandfathered().first, isFalse);
        expect(await db.countLiveRoutines(), equals(0));

        final r1 = await db.insertRoutineWithInitialState(
          routine: RoutinesCompanion(
            Name: const Value('Live 1'),
            IntervalSeconds: const Value(3600),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
          ),
          nextTriggerTime: DateTime(2026, 1, 1, 10, 0),
        );
        final r2 = await db.insertRoutineWithInitialState(
          routine: RoutinesCompanion(
            Name: const Value('Live 2'),
            IntervalSeconds: const Value(3600),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
          ),
          nextTriggerTime: DateTime(2026, 1, 1, 11, 0),
        );
        expect(await db.countLiveRoutines(), equals(2));

        await db.softDeleteRoutine(r2);
        expect(await db.countLiveRoutines(), equals(1));
        expect(r1, greaterThan(0));
      },
    );

    test(
      'v17 to v18 migration grandfathers devices that already had routines',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_mig_v18_');
        final dbPath = p.join(tempDir.path, 'legacy_v17.db');
        try {
          final raw = sqlite3.sqlite3.open(dbPath);
          raw.execute('''
            CREATE TABLE routines (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              snooze_seconds INTEGER NOT NULL DEFAULT 300,
              interval_seconds INTEGER NOT NULL,
              max_times_per_day INTEGER NOT NULL DEFAULT 0,
              day_start_seconds INTEGER NOT NULL DEFAULT 0,
              max_times_per_day_enabled INTEGER NOT NULL DEFAULT 0,
              enabled_weekdays INTEGER NOT NULL DEFAULT 127,
              drift_compensation_type_code INTEGER NOT NULL,
              show_preview INTEGER NOT NULL DEFAULT 1,
              vibrate INTEGER NOT NULL DEFAULT 1,
              volume INTEGER NOT NULL DEFAULT 50,
              fade_in INTEGER NOT NULL DEFAULT 0,
              audio_uri TEXT NULL,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
              modified_at INTEGER NULL,
              deleted INTEGER NOT NULL DEFAULT 0
            );
          ''');
          raw.execute('''
            INSERT INTO routines (name, interval_seconds, drift_compensation_type_code)
            VALUES ('Early Adopter Alarm', 3600, 0);
          ''');
          raw.execute('PRAGMA user_version = 17;');
          raw.close();

          final upgraded = RA_Database.openForIsolate(dbPath);
          try {
            expect(await upgraded.isLegacyProGrandfathered(), isTrue);
            expect(await upgraded.watchLegacyProGrandfathered().first, isTrue);
            expect(await upgraded.countLiveRoutines(), equals(1));
          } finally {
            await upgraded.close();
          }
        } finally {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        }
      },
    );

    test(
      'v17 to v18 migration does NOT grandfather devices with zero routines',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_mig_empty_');
        final dbPath = p.join(tempDir.path, 'empty_v17.db');
        try {
          final raw = sqlite3.sqlite3.open(dbPath);
          raw.execute('''
            CREATE TABLE routines (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              snooze_seconds INTEGER NOT NULL DEFAULT 300,
              interval_seconds INTEGER NOT NULL,
              max_times_per_day INTEGER NOT NULL DEFAULT 0,
              day_start_seconds INTEGER NOT NULL DEFAULT 0,
              max_times_per_day_enabled INTEGER NOT NULL DEFAULT 0,
              enabled_weekdays INTEGER NOT NULL DEFAULT 127,
              drift_compensation_type_code INTEGER NOT NULL,
              show_preview INTEGER NOT NULL DEFAULT 1,
              vibrate INTEGER NOT NULL DEFAULT 1,
              volume INTEGER NOT NULL DEFAULT 50,
              fade_in INTEGER NOT NULL DEFAULT 0,
              audio_uri TEXT NULL,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
              modified_at INTEGER NULL,
              deleted INTEGER NOT NULL DEFAULT 0
            );
          ''');
          raw.execute('PRAGMA user_version = 17;');
          raw.close();

          final upgraded = RA_Database.openForIsolate(dbPath);
          try {
            expect(await upgraded.isLegacyProGrandfathered(), isFalse);
            expect(await upgraded.watchLegacyProGrandfathered().first, isFalse);
          } finally {
            await upgraded.close();
          }
        } finally {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        }
      },
    );

    test(
      'watchLogEntries respects limit/since and pruneOldLogs preserves recoverable delete logs',
      () async {
        final now = DateTime.now();
        final oldTime = now.subtract(const Duration(days: 400));
        final recentTime = now.subtract(const Duration(days: 5));

        final liveRoutineId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Live Routine'),
            IntervalSeconds: const Value(3600),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
          ),
        );
        final softDeletedRoutineId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Deleted Routine'),
            IntervalSeconds: const Value(3600),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
            Deleted: const Value(true),
          ),
        );

        // 1. Old normal log on live routine -> should be pruned.
        final oldLiveLog = await db.insertLogEntry(
          LogEntriesCompanion(
            RoutineId: Value(liveRoutineId),
            Timestamp: Value(oldTime),
            LogActionTypeCode: Value(LogActionTypeCodeEnum.Dismiss.index),
          ),
        );
        // 2. Old Delete log on live (recovered) routine -> should be pruned.
        final oldRecoveredDeleteLog = await db.insertLogEntry(
          LogEntriesCompanion(
            RoutineId: Value(liveRoutineId),
            Timestamp: Value(oldTime),
            LogActionTypeCode: Value(LogActionTypeCodeEnum.Delete.index),
          ),
        );
        // 3. Old Delete log on still soft-deleted routine -> MUST be preserved!
        final oldRecoverableDeleteLog = await db.insertLogEntry(
          LogEntriesCompanion(
            RoutineId: Value(softDeletedRoutineId),
            Timestamp: Value(oldTime),
            LogActionTypeCode: Value(LogActionTypeCodeEnum.Delete.index),
          ),
        );
        // 4. Old Ring log on soft-deleted routine -> should be pruned (not a Delete log).
        final oldDeletedRoutineRingLog = await db.insertLogEntry(
          LogEntriesCompanion(
            RoutineId: Value(softDeletedRoutineId),
            Timestamp: Value(oldTime),
            LogActionTypeCode: Value(LogActionTypeCodeEnum.Ring.index),
          ),
        );
        // 5. Recent soft-deleted log row -> should be pruned because Deleted == true.
        final softDeletedLogRow = await db.insertLogEntry(
          LogEntriesCompanion(
            RoutineId: Value(liveRoutineId),
            Timestamp: Value(recentTime),
            LogActionTypeCode: Value(LogActionTypeCodeEnum.Ring.index),
            Deleted: const Value(true),
          ),
        );
        // 6. Recent live log -> MUST be preserved.
        final recentLiveLog = await db.insertLogEntry(
          LogEntriesCompanion(
            RoutineId: Value(liveRoutineId),
            Timestamp: Value(recentTime),
            LogActionTypeCode: Value(LogActionTypeCodeEnum.Dismiss.index),
          ),
        );

        // Verify limit & since filtering before prune.
        final capped = await db.watchLogEntries(limit: 2).first;
        expect(capped.length, equals(2));
        final sinceRecent = await db
            .watchLogEntries(since: now.subtract(const Duration(days: 10)))
            .first;
        expect(sinceRecent.map((e) => e.Id), equals([recentLiveLog]));
        final forExport = await db.getLogEntriesForExport(limit: 3);
        expect(forExport.length, equals(3));

        await db.pruneOldLogs(maxAge: const Duration(days: 365));

        final remainingAll = await db.select(db.logEntries).get();
        final remainingIds = remainingAll.map((e) => e.Id).toSet();
        expect(remainingIds, contains(recentLiveLog));
        expect(remainingIds, contains(oldRecoverableDeleteLog));
        expect(remainingIds, isNot(contains(oldLiveLog)));
        expect(remainingIds, isNot(contains(oldRecoveredDeleteLog)));
        expect(remainingIds, isNot(contains(oldDeletedRoutineRingLog)));
        expect(remainingIds, isNot(contains(softDeletedLogRow)));
      },
    );

    test(
      'v18 to v19 migration adds swing-roster columns with safe defaults and preserves existing rows',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ra_mig_v19_');
        final dbPath = p.join(tempDir.path, 'legacy_v18.db');
        try {
          final raw = sqlite3.sqlite3.open(dbPath);
          raw.execute('''
            CREATE TABLE routines (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              snooze_seconds INTEGER NOT NULL DEFAULT 300,
              interval_seconds INTEGER NOT NULL,
              max_times_per_day INTEGER NOT NULL DEFAULT 0,
              day_start_seconds INTEGER NOT NULL DEFAULT 0,
              max_times_per_day_enabled INTEGER NOT NULL DEFAULT 0,
              enabled_weekdays INTEGER NOT NULL DEFAULT 127,
              drift_compensation_type_code INTEGER NOT NULL,
              show_preview INTEGER NOT NULL DEFAULT 1,
              vibrate INTEGER NOT NULL DEFAULT 1,
              volume INTEGER NOT NULL DEFAULT 50,
              fade_in INTEGER NOT NULL DEFAULT 0,
              audio_uri TEXT NULL,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
              modified_at INTEGER NULL,
              deleted INTEGER NOT NULL DEFAULT 0
            );
          ''');
          raw.execute('''
            CREATE TABLE app_meta (
              key TEXT NOT NULL PRIMARY KEY,
              value TEXT NOT NULL,
              updated_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
            );
          ''');
          raw.execute('''
            INSERT INTO routines (name, interval_seconds, drift_compensation_type_code)
            VALUES ('Pre-Swing Routine', 14400, 0);
          ''');
          raw.execute('''
            INSERT INTO app_meta ("key", "value")
            VALUES ('legacy_pro_grandfathered', 'true');
          ''');
          raw.execute('PRAGMA user_version = 18;');
          raw.close();

          final upgraded = RA_Database.openForIsolate(dbPath);
          try {
            final routines = await upgraded.watchAllRoutines().first;
            expect(routines, hasLength(1));
            final existing = routines.first;
            expect(existing.Name, equals('Pre-Swing Routine'));
            expect(existing.CycleOnDays, equals(0));
            expect(existing.CycleOffDays, equals(0));
            expect(existing.CycleAnchorEpochDay, isNull);
            expect(await upgraded.isLegacyProGrandfathered(), isTrue);

            final swingId = await upgraded.insertRoutine(
              RoutinesCompanion(
                Name: const Value('WA FIFO 8/6'),
                IntervalSeconds: const Value(43200),
                CycleOnDays: const Value(8),
                CycleOffDays: const Value(6),
                CycleAnchorEpochDay: const Value(20605),
                DriftCompensationTypeCode: Value(
                  DriftCompensationTypeCodeEnum.ActualDismissal.index,
                ),
              ),
            );
            final inserted = await upgraded.getRoutineById(swingId);
            expect(inserted.CycleOnDays, equals(8));
            expect(inserted.CycleOffDays, equals(6));
            expect(inserted.CycleAnchorEpochDay, equals(20605));
          } finally {
            await upgraded.close();
          }
        } finally {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        }
      },
    );
  });
}
