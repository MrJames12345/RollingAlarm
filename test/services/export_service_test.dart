import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';
import 'package:rolling_alarm/services/export.dart';
import 'package:rolling_alarm/services/pdf.dart';
import 'package:rolling_alarm/services/swing_roster.dart';

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
        expect(r.EnabledWeekdays, equals(0x7F));
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
        expect(r.MaxTimesPerDay, 1);
        expect(r.DayStartSeconds, 0);
        expect(
          r.DriftCompensationTypeCode,
          DriftCompensationTypeCodeEnum.ActualDismissal.index,
        );
        expect(r.ShowPreview, isTrue);
        expect(r.Vibrate, isTrue);
        expect(r.Volume, equals(50));
        expect(r.FadeIn, isFalse);
        expect(r.AudioUri, isNull);
        expect(r.IsActive, isTrue);
      },
    );

    test('rejects payload larger than 512 KB', () {
      final oversized = 'RA1:${'A' * (RA_ExportService.maxPayloadBytes + 1)}';
      expect(
        () => RA_ExportService.decodeExportString(oversized),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('512 KB'),
          ),
        ),
      );
    });

    test('rejects payload with more than 50 routines', () {
      final payload = {
        'version': 10,
        'routines': List<Map<String, Object?>>.generate(
          51,
          (i) => {'Name': 'Routine $i', 'IntervalSeconds': 3600},
        ),
      };
      final encoded = 'RA1:${base64Encode(utf8.encode(jsonEncode(payload)))}';
      expect(
        () => RA_ExportService.decodeExportString(encoded),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('50'),
          ),
        ),
      );
    });

    test('rejects payload with non-object routine entries', () {
      final payload = {
        'version': 10,
        'routines': ['not-an-object', 123],
      };
      final encoded = 'RA1:${base64Encode(utf8.encode(jsonEncode(payload)))}';
      expect(
        () => RA_ExportService.decodeExportString(encoded),
        throwsA(isA<FormatException>()),
      );
    });

    test('clamps and sanitizes out-of-range RA1 imported fields', () async {
      final longName = 'X' * 300;
      final payload = {
        'version': 10,
        'routines': [
          {
            'Name': '   ',
            'IntervalSeconds': 0,
            'SnoozeSeconds': -120,
            'Volume': 1,
            'DayStartSeconds': -50,
            'MaxTimesPerDayEnabled': true,
            'MaxTimesPerDay': 0,
            'EnabledWeekdays': 0,
            'DriftCompensationTypeCode': 999,
          },
          {
            'Name': longName,
            'IntervalSeconds': 9999999,
            'SnoozeSeconds': 99999,
            'Volume': 250,
            'DayStartSeconds': 100000,
            'MaxTimesPerDayEnabled': true,
            'MaxTimesPerDay': 500,
            'EnabledWeekdays': 0x85, // bit 7 stripped -> 0x05
            'DriftCompensationTypeCode': -1,
          },
        ],
      };
      final encoded = 'RA1:${base64Encode(utf8.encode(jsonEncode(payload)))}';
      final ids = await RA_ExportService.importFromBase64(db, encoded);
      expect(ids, hasLength(2));

      final low = await db.getRoutineById(ids[0]);
      expect(low.Name, equals('Imported Routine'));
      expect(low.IntervalSeconds, equals(60));
      expect(low.SnoozeSeconds, equals(60));
      expect(low.Volume, equals(5));
      expect(low.DayStartSeconds, equals(0));
      expect(low.MaxTimesPerDayEnabled, isTrue);
      expect(low.MaxTimesPerDay, equals(1));
      expect(low.EnabledWeekdays, equals(0x7F));
      expect(
        low.DriftCompensationTypeCode,
        equals(DriftCompensationTypeCodeEnum.ActualDismissal.index),
      );

      final high = await db.getRoutineById(ids[1]);
      expect(high.Name.length, equals(255));
      expect(high.IntervalSeconds, equals(604800));
      expect(high.SnoozeSeconds, equals(7200));
      expect(high.Volume, equals(100));
      expect(high.DayStartSeconds, equals(86399));
      expect(high.MaxTimesPerDay, equals(99));
      expect(high.EnabledWeekdays, equals(0x05));
      expect(
        high.DriftCompensationTypeCode,
        equals(DriftCompensationTypeCodeEnum.ActualDismissal.index),
      );
    });

    test(
      'round-trips swing roster columns, exports SwingSchedule label, and clamps CycleOnDays/CycleOffDays to 0..60',
      () async {
        final anchorDay = RA_SwingRosterSchedule.localEpochDay(
          DateTime(2026, 6, 1),
        );
        final id = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('WA FIFO 8/6 Day Swing'),
            IntervalSeconds: const Value(43200),
            SnoozeSeconds: const Value(600),
            MaxTimesPerDayEnabled: const Value(true),
            MaxTimesPerDay: const Value(1),
            DayStartSeconds: const Value(5 * 3600),
            CycleOnDays: const Value(8),
            CycleOffDays: const Value(6),
            CycleAnchorEpochDay: Value(anchorDay),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
          ),
        );
        final routine = await db.getRoutineById(id);

        final singleCode = RA_ExportService.exportSingleRoutine(routine);
        expect(singleCode, startsWith('RA1:'));
        final decoded = RA_ExportService.decodeExportString(singleCode);
        final first =
            (decoded['routines'] as List<Object?>).first as Map<Object?, Object?>;
        expect(first['CycleOnDays'], equals(8));
        expect(first['CycleOffDays'], equals(6));
        expect(first['CycleAnchorEpochDay'], equals(anchorDay));
        expect(first['SwingSchedule'], equals('8/6 Swing (8d On / 6d Off)'));

        final db2 = RA_Database.forTesting(NativeDatabase.memory());
        try {
          final importedIds = await RA_ExportService.importFromBase64(
            db2,
            singleCode,
          );
          final imported = await db2.getRoutineById(importedIds.single);
          expect(imported.CycleOnDays, equals(8));
          expect(imported.CycleOffDays, equals(6));
          expect(imported.CycleAnchorEpochDay, equals(anchorDay));

          // Verify clamping for out-of-range swing values.
          final clampedPayload = {
            'version': 11,
            'routines': [
              {
                'Name': 'High Swing',
                'IntervalSeconds': 3600,
                'CycleOnDays': 120,
                'CycleOffDays': 95,
                'CycleAnchorEpochDay': anchorDay,
              },
              {
                'Name': 'Negative Swing',
                'IntervalSeconds': 3600,
                'CycleOnDays': -4,
                'CycleOffDays': -10,
                'CycleAnchorEpochDay': anchorDay,
              },
            ],
          };
          final clampedEncoded =
              'RA1:${base64Encode(utf8.encode(jsonEncode(clampedPayload)))}';
          final clampedIds = await RA_ExportService.importFromBase64(
            db2,
            clampedEncoded,
          );
          final high = await db2.getRoutineById(clampedIds[0]);
          expect(high.CycleOnDays, equals(60));
          expect(high.CycleOffDays, equals(60));
          expect(high.CycleAnchorEpochDay, equals(anchorDay));

          final low = await db2.getRoutineById(clampedIds[1]);
          expect(low.CycleOnDays, equals(0));
          expect(low.CycleOffDays, equals(0));
          expect(low.CycleAnchorEpochDay, isNull);
        } finally {
          await db2.close();
        }
      },
    );

    test(
      'extracts and imports RA1 presets from share URLs, unencoded query params, and multi-line Reddit comments',
      () async {
        final anchorDay = RA_SwingRosterSchedule.localEpochDay(
          DateTime(2026, 6, 1),
        );
        final id = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Nursing 4/4 Shift'),
            IntervalSeconds: const Value(43200),
            SnoozeSeconds: const Value(600),
            MaxTimesPerDayEnabled: const Value(true),
            MaxTimesPerDay: const Value(1),
            DayStartSeconds: const Value(6 * 3600),
            CycleOnDays: const Value(4),
            CycleOffDays: const Value(4),
            CycleAnchorEpochDay: Value(anchorDay),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
          ),
        );
        final routine = await db.getRoutineById(id);
        final exportedAt = DateTime.utc(2026, 6, 1, 6, 0, 0);
        final code = RA_ExportService.exportSingleRoutine(
          routine,
          exportedAt: exportedAt,
        );
        final url = RA_ExportService.buildShareablePresetUrl(
          routine,
          preEncodedCode: code,
        );
        final message = RA_ExportService.buildShareablePresetMessage(
          routine,
          exportedAt: exportedAt,
        );

        expect(
          url,
          startsWith('https://casellaweb.com.au/rolling-alarm?preset=RA1:'),
        );
        expect(message, contains('Nursing 4/4 Shift'));
        expect(message, contains('4/4 Swing (4d On / 4d Off)'));
        expect(message, contains(url));
        expect(message, contains(code));

        // 1. Direct URL paste
        expect(RA_ExportService.tryExtractValidPreset(url), equals(code));
        final fromUrl = await RA_ExportService.importFromBase64(db, url);
        expect(fromUrl, hasLength(1));

        // 2. URL with unencoded '+' turned into space + extra UTM params
        final rawBase64 = code.substring('RA1:'.length);
        final urlWithSpaces =
            'https://casellaweb.com.au/rolling-alarm?utm_source=reddit&preset=RA1:${rawBase64.replaceAll('+', ' ')}';
        final fromSpacedUrl = await RA_ExportService.importFromBase64(
          db,
          urlWithSpaces,
        );
        expect(fromSpacedUrl, hasLength(1));

        // 3. Multi-line Reddit comment containing URL + surrounding text
        final redditComment =
            'Hey r/FIFO, here is my exact ward shift schedule!\n'
            'Link: ($url).\n'
            'Works 100% offline on site.';
        final fromComment = await RA_ExportService.importFromBase64(
          db,
          redditComment,
        );
        expect(fromComment, hasLength(1));

        // 4. Full shareable message pasted directly
        final fromMessage = await RA_ExportService.importFromBase64(
          db,
          message,
        );
        expect(fromMessage, hasLength(1));

        // 5. Invalid clipboard text returns null cleanly
        expect(
          RA_ExportService.tryExtractValidPreset('Just normal clipboard text'),
          isNull,
        );
      },
    );

    test(
      'handles base64 containing "+" across space-munged URLs, scheme-less URLs, raw percent-encoded tokens, line-wrapped blocks, and broken-link fallback',
      () async {
        // Construct a payload whose standard base64 encoding is GUARANTEED to
        // contain both '+' and '/' characters (`0xfb`, `0xff` -> `+/`, or `>?`).
        final payloadWithPlusAndSlash = {
          'version': 11,
          'routines': [
            {
              'Name': 'Dose >> ?? ~~ FIFO + Ward',
              'IntervalSeconds': 14400,
              'CycleOnDays': 8,
              'CycleOffDays': 6,
              'CycleAnchorEpochDay': 20605,
            },
          ],
        };
        final rawB64 = base64Encode(
          utf8.encode(jsonEncode(payloadWithPlusAndSlash)),
        );
        expect(rawB64, contains('+'));
        final code = 'RA1:$rawB64';
        final encodedB64 = Uri.encodeQueryComponent(rawB64);

        // 1. Space-munged URL where real '+' characters became literal spaces
        final spaceMungedUrl =
            'Check this link https://casellaweb.com.au/rolling-alarm?utm_source=reddit&preset=RA1:${rawB64.replaceAll('+', ' ')} works great!';
        expect(RA_ExportService.tryExtractValidPreset(spaceMungedUrl), equals(code));
        expect(
          (await RA_ExportService.importFromBase64(db, spaceMungedUrl)).length,
          equals(1),
        );

        // 2. Scheme-less URL copied from address bar with percent-encoded base64
        final schemelessUrl =
            'casellaweb.com.au/rolling-alarm?preset=RA1:$encodedB64';
        expect(RA_ExportService.tryExtractValidPreset(schemelessUrl), equals(code));

        // 3. Direct copied `?preset=` value `RA1:...%2B...%3D`
        final directPercentEncoded = 'RA1:$encodedB64';
        expect(
          RA_ExportService.tryExtractValidPreset(directPercentEncoded),
          equals(code),
        );

        // 4. Direct URL-safe unpadded base64
        final urlSafe =
            'RA1:${rawB64.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '')}';
        expect(RA_ExportService.tryExtractValidPreset(urlSafe), equals(code));

        // 5. Line-wrapped raw RA1: block (email / SMS wrap)
        final wrapped = '${code.substring(0, 24)}\n${code.substring(24)}';
        expect(RA_ExportService.tryExtractValidPreset(wrapped), equals(code));

        // 6. Truncated/broken URL followed by intact raw RA1: code falls back cleanly
        final brokenLinkPlusRawCode =
            'Link got cut off: https://casellaweb.com.au/rolling-alarm?preset=RA1:eyJ2ZXJzaW9\n'
            'Backup code:\n'
            '$code';
        expect(
          RA_ExportService.tryExtractValidPreset(brokenLinkPlusRawCode),
          equals(code),
        );
      },
    );

    test(
      'exportSingleRoutine forces active preset, full backup preserves paused state cleanly, and import clamps anchor & half-configured swing',
      () async {
        final pausedId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Paused Shift'),
            IntervalSeconds: const Value(43200),
            IsActive: const Value(false),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
          ),
        );
        final pausedRoutine = await db.getRoutineById(pausedId);

        // Single-routine preset share always exports active for recipient.
        final sharedCode = RA_ExportService.exportSingleRoutine(pausedRoutine);
        final recipientDb = RA_Database.forTesting(NativeDatabase.memory());
        try {
          final sharedIds = await RA_ExportService.importFromBase64(
            recipientDb,
            sharedCode,
          );
          final sharedImported = await recipientDb.getRoutineById(
            sharedIds.single,
          );
          final sharedState = await recipientDb.getRoutineState(
            sharedIds.single,
          );
          expect(sharedImported.IsActive, isTrue);
          expect(sharedState?.PausedAt, isNull);

          // Full backup preserves IsActive: false AND sets PausedAt consistently.
          final backupCode = await RA_ExportService.exportToBase64(db);
          final backupIds = await RA_ExportService.importFromBase64(
            recipientDb,
            backupCode,
          );
          final backupImported = await recipientDb.getRoutineById(
            backupIds.single,
          );
          final backupState = await recipientDb.getRoutineState(
            backupIds.single,
          );
          expect(backupImported.IsActive, isFalse);
          expect(backupState?.PausedAt, isNotNull);

          // Extreme anchor epoch day is clamped and half-configured swing normalized.
          final hostilePayload = {
            'version': 11,
            'routines': [
              {
                'Name': 'Extreme Anchor',
                'IntervalSeconds': 3600,
                'CycleOnDays': 8,
                'CycleOffDays': 6,
                'CycleAnchorEpochDay': 999999999999,
              },
              {
                'Name': 'Half Swing',
                'IntervalSeconds': 3600,
                'CycleOnDays': 8,
                'CycleOffDays': 0,
                'CycleAnchorEpochDay': 20605,
              },
            ],
          };
          final hostileCode =
              'RA1:${base64Encode(utf8.encode(jsonEncode(hostilePayload)))}';
          final hostileIds = await RA_ExportService.importFromBase64(
            recipientDb,
            hostileCode,
          );
          final clamped = await recipientDb.getRoutineById(hostileIds[0]);
          expect(
            clamped.CycleAnchorEpochDay,
            equals(RA_ExportService.maxAnchorEpochDay),
          );
          expect(
            () => RA_SwingRosterSchedule.dateFromEpochDay(
              clamped.CycleAnchorEpochDay!,
            ),
            returnsNormally,
          );

          final half = await recipientDb.getRoutineById(hostileIds[1]);
          expect(half.CycleOnDays, equals(0));
          expect(half.CycleOffDays, equals(0));
          expect(half.CycleAnchorEpochDay, isNull);
        } finally {
          await recipientDb.close();
        }
      },
    );

    test(
      'RA_PdfService builds valid multi-page PDF bytes with branded verification footer (with and without TTF fonts)',
      () async {
        final regularFontBytes = File(
          'assets/fonts/Inter-Regular.ttf',
        ).readAsBytesSync();
        final boldFontBytes = File(
          'assets/fonts/Inter-Bold.ttf',
        ).readAsBytesSync();
        final manyRows = List<List<String>>.generate(
          250,
          (i) => [
            'Jun 1, 2026 7:00 AM',
            'Medication Routine #${i + 1}',
            'Dismiss',
            '4h',
          ],
        );
        final bytes = await RA_PdfService.buildLogsPdfBytes(
          manyRows,
          regularFontBytes: regularFontBytes,
          boldFontBytes: boldFontBytes,
        );
        expect(bytes, isNotEmpty);
        expect(String.fromCharCodes(bytes.take(5)), equals('%PDF-'));
        final pdfAscii = latin1.decode(bytes, allowInvalid: true);
        expect(pdfAscii, contains(RA_PdfService.footerVerificationUrl));

        // Fallback path when font bytes are absent must also succeed cleanly.
        final fallbackBytes = await RA_PdfService.buildLogsPdfBytes(
          manyRows.take(5).toList(),
        );
        expect(String.fromCharCodes(fallbackBytes.take(5)), equals('%PDF-'));
      },
    );
  });
}
