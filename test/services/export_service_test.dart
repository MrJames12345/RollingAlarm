import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';
import 'package:rolling_alarm/services/export.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('RA_ExportService Tests', () {
    late RA_Database db;

    setUp(() {
      db = RA_Database.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('base64 round trip exports and imports routines accurately', () async {
      await db.insertRoutine(
        RoutinesCompanion(
          Name: const Value('Morning Routine'),
          IntervalSeconds: const Value(16200),
          SnoozeSeconds: const Value(600),
          DriftCompensationTypeCode: Value(
            DriftCompensationTypeCodeEnum.ActualDismissal.index,
          ),
          ShowPreview: const Value(true),
          Vibrate: const Value(false),
          Volume: const Value(60),
          FadeIn: const Value(true),
          AudioUri: const Value('default_ringtone'),
          IsActive: const Value(true),
        ),
      );

      final exportString = await RA_ExportService.exportToBase64(db);
      expect(exportString, startsWith('RA1:'));

      // Create a fresh database to import into
      final db2 = RA_Database.forTesting(NativeDatabase.memory());
      try {
        final importedIds = await RA_ExportService.importFromBase64(
          db2,
          exportString,
        );
        expect(importedIds.length, equals(1));

        // An imported routine must be schedulable straight away, which means it
        // needs its own state row seeded one interval out.
        final state = await db2.getRoutineState(importedIds.single);
        expect(state, isNotNull);
        expect(state!.NextTriggerTime, isNotNull);
        expect(state.IsRinging, isFalse);

        final routines = await db2.watchAllRoutines().first;
        expect(routines.length, equals(1));
        final r = routines.first;
        expect(r.Name, equals('Morning Routine'));
        expect(r.IntervalSeconds, equals(4 * 3600 + 30 * 60));
        expect(r.SnoozeSeconds, equals(600));
        expect(
          r.DriftCompensationTypeCode,
          equals(DriftCompensationTypeCodeEnum.ActualDismissal.index),
        );
        expect(r.ShowPreview, isTrue);
        expect(r.Vibrate, isFalse);
        expect(r.Volume, equals(60));
        expect(r.FadeIn, isTrue);
        expect(r.AudioUri, equals('default_ringtone'));
        expect(r.IsActive, isTrue);
      } finally {
        await db2.close();
      }
    });

    test('rejects malformed strings missing prefix', () {
      expect(
        () =>
            RA_ExportService.decodeExportString('INVALID_PREFIX_c29tZSBkYXRh'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects malformed base64 payload', () {
      expect(
        () => RA_ExportService.decodeExportString('RA1:not!!!valid###base64'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects wrong version payload', () {
      // Valid base64 of {"version":999,"routines":[]} so the failure comes from
      // the version check rather than from decoding.
      final encoded =
          'RA1:${base64Encode(utf8.encode('{"version":999,"routines":[]}'))}';
      expect(
        () => RA_ExportService.decodeExportString(encoded),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Unsupported export version'),
          ),
        ),
      );
    });

    test('rejects payload with a missing routines list', () {
      final encoded = 'RA1:${base64Encode(utf8.encode('{"version":1}'))}';
      expect(
        () => RA_ExportService.decodeExportString(encoded),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('routines'),
          ),
        ),
      );
    });

    test(
      'imports version 1 exports folding hours and minutes into IntervalSeconds',
      () async {
        final v1Payload = {
          'version': 1,
          'routines': [
            {
              'Name': 'Legacy',
              'SnoozeMinutes': 5,
              'IntervalHours': 2,
              'IntervalMinutes': 15,
              'DriftCompensationTypeCode': 0,
              'ShowPreview': true,
              'AudioUri': null,
              'IsActive': true,
            },
          ],
        };
        final encoded =
            'RA1:${base64Encode(utf8.encode(jsonEncode(v1Payload)))}';
        final ids = await RA_ExportService.importFromBase64(db, encoded);
        expect(ids, hasLength(1));
        final r = await db.getRoutineById(ids.single);
        expect(r.IntervalSeconds, 2 * 3600 + 15 * 60);
      },
    );

    test(
      'imports sparse old payloads with defaults and ignores extra fields',
      () async {
        final sparsePayload = {
          'version': 1,
          'routines': [
            {
              'Name': 'Sparse',
              'IntervalHours': 1,
              'IntervalMinutes': 0,
              // Removed / unknown keys must not break import.
              'MaxSnoozes': 3,
              'AutoSnoozeOnIgnore': true,
              'FutureOnlyField': 'ignored',
            },
          ],
        };
        final encoded =
            'RA1:${base64Encode(utf8.encode(jsonEncode(sparsePayload)))}';
        final ids = await RA_ExportService.importFromBase64(db, encoded);
        expect(ids, hasLength(1));
        final r = await db.getRoutineById(ids.single);
        expect(r.Name, 'Sparse');
        expect(r.IntervalSeconds, 3600);
        expect(r.SnoozeSeconds, 300);
        expect(r.MaxTimesPerDayEnabled, isFalse);
        expect(r.MaxTimesPerDay, 0);
        expect(r.DayStartSeconds, 0);
        expect(
          r.DriftCompensationTypeCode,
          DriftCompensationTypeCodeEnum.ActualDismissal.index,
        );
        expect(r.ShowPreview, isTrue);
        expect(r.Vibrate, isTrue);
        expect(r.Volume, equals(100));
        expect(r.FadeIn, isFalse);
        expect(r.AudioUri, isNull);
        expect(r.IsActive, isTrue);
      },
    );
  });
}
