import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';
import 'package:rolling_alarm/enums/log_action_type_code.dart';

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
  });
}
