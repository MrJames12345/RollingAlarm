import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';
import 'package:rolling_alarm/services/daily_ring_limit.dart';

/// Versioned JSON-to-base64 export/import service.
/// Format: `RA1:` followed by base64-encoded JSON.
class RA_ExportService {
  RA_ExportService._();

  static const String _versionPrefix = 'RA1:';
  static const int _currentVersion = 10;
  static const int _minSupportedVersion = 1;

  /// Hard bounds defending against malformed or hostile RA1 import strings.
  static const int maxPayloadBytes = 512 * 1024;
  static const int maxRoutinesPerImport = 50;
  static const int minIntervalSeconds = 60;
  static const int maxIntervalSeconds = 604800; // 7 days
  static const int minSnoozeSeconds = 60;
  static const int maxSnoozeSeconds = 7200; // 2 hours
  static const int minVolume = 5;
  static const int maxVolume = 100;
  static const int minDayStartSeconds = 0;
  static const int maxDayStartSeconds = 86399;
  static const int minMaxTimesPerDay = 1;
  static const int maxMaxTimesPerDay = 99;
  static const int maxNameLength = 255;

  /// Matches the new-routine form default (2h 30m) when interval is absent.
  static const int _defaultIntervalSeconds = 9000;
  static const int _defaultSnoozeSeconds = 300;
  static const String _defaultName = 'Imported Routine';

  /// Exports all routines to a versioned base64 string.
  static Future<String> exportToBase64(RA_Database db) async {
    final routines = await (db.select(
      db.routines,
    )..where((r) => r.Deleted.equals(false))).get();

    final payload = <String, Object?>{
      'version': _currentVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'routines': routines
          .map(
            (r) => <String, Object?>{
              'Name': r.Name,
              'SnoozeSeconds': r.SnoozeSeconds,
              'IntervalSeconds': r.IntervalSeconds,
              'MaxTimesPerDayEnabled': r.MaxTimesPerDayEnabled,
              'MaxTimesPerDay': r.MaxTimesPerDay,
              'DayStartSeconds': r.DayStartSeconds,
              'EnabledWeekdays': r.EnabledWeekdays,
              'DriftCompensationTypeCode': r.DriftCompensationTypeCode,
              'ShowPreview': r.ShowPreview,
              'Vibrate': r.Vibrate,
              'Volume': r.Volume,
              'FadeIn': r.FadeIn,
              'AudioUri': r.AudioUri,
              'IsActive': r.IsActive,
            },
          )
          .toList(),
    };

    final jsonString = jsonEncode(payload);
    final base64String = base64Encode(utf8.encode(jsonString));
    return '$_versionPrefix$base64String';
  }

  /// Validates and decodes a base64 export string.
  /// Returns the decoded payload map or throws [FormatException] on invalid input.
  static Map<String, Object?> decodeExportString(String exportString) {
    if (exportString.length > maxPayloadBytes ||
        utf8.encode(exportString).length > maxPayloadBytes) {
      throw const FormatException(
        'Export payload exceeds maximum allowed size of 512 KB',
      );
    }
    if (!exportString.startsWith(_versionPrefix)) {
      throw const FormatException(
        'Invalid export format: missing version prefix "$_versionPrefix"',
      );
    }

    final payload = _decodeJsonPayload(
      exportString.substring(_versionPrefix.length),
    );

    final version = payload['version'];
    if (version is! int ||
        version < _minSupportedVersion ||
        version > _currentVersion) {
      throw FormatException(
        'Unsupported export version: $version '
        '(expected $_minSupportedVersion-$_currentVersion)',
      );
    }

    final rawRoutines = payload['routines'];
    if (rawRoutines is! List<Object?>) {
      throw const FormatException('Missing or invalid "routines" field');
    }
    if (rawRoutines.length > maxRoutinesPerImport) {
      throw FormatException(
        'Export contains ${rawRoutines.length} routines '
        '(maximum $maxRoutinesPerImport allowed per import)',
      );
    }
    for (final item in rawRoutines) {
      if (item is! Map<Object?, Object?>) {
        throw const FormatException(
          'Invalid entry in "routines": each routine must be a JSON object',
        );
      }
    }

    return payload;
  }

  static Map<String, Object?> _decodeJsonPayload(String base64Part) {
    try {
      final jsonString = utf8.decode(base64Decode(base64Part));
      final Object? decoded = jsonDecode(jsonString);
      if (decoded is! Map<Object?, Object?> ||
          !decoded.containsKey('version')) {
        throw const FormatException(
          'Missing "version" field in export payload',
        );
      }
      return Map<String, Object?>.from(decoded);
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Invalid export payload: $e');
    }
  }

  static int? _readInt(Map<String, Object?> map, String key) {
    final Object? value = map[key];
    if (value is int) return value;
    if (value is num && value.isFinite) return value.toInt();
    return null;
  }

  static bool? _readBool(Map<String, Object?> map, String key) {
    final Object? value = map[key];
    return value is bool ? value : null;
  }

  static String? _readString(Map<String, Object?> map, String key) {
    final Object? value = map[key];
    return value is String ? value : null;
  }

  /// Total interval seconds from a routine map, clamped to [minIntervalSeconds..maxIntervalSeconds].
  ///
  /// Version 4+ stores a single [IntervalSeconds] total. Older exports used
  /// hours + minutes + remainder seconds. Missing interval data uses
  /// [_defaultIntervalSeconds].
  static int _intervalSecondsFromMap(Map<String, Object?> r) {
    final hours = _readInt(r, 'IntervalHours');
    final minutes = _readInt(r, 'IntervalMinutes');
    final seconds = _readInt(r, 'IntervalSeconds');
    final int raw;
    if (hours == null && minutes == null && seconds == null) {
      raw = _defaultIntervalSeconds;
    } else if (hours != null || minutes != null) {
      raw = ((hours ?? 0) * 3600) + ((minutes ?? 0) * 60) + (seconds ?? 0);
    } else {
      raw = seconds ?? _defaultIntervalSeconds;
    }
    return raw.clamp(minIntervalSeconds, maxIntervalSeconds);
  }

  /// Total snooze seconds from a routine map, clamped to [minSnoozeSeconds..maxSnoozeSeconds].
  ///
  /// Version 8+ stores [SnoozeSeconds]. Older exports used [SnoozeMinutes].
  /// Missing snooze data uses [_defaultSnoozeSeconds].
  static int _snoozeSecondsFromMap(Map<String, Object?> r) {
    final snoozeSecs = _readInt(r, 'SnoozeSeconds');
    final int raw;
    if (snoozeSecs != null) {
      raw = snoozeSecs;
    } else {
      final snoozeMins = _readInt(r, 'SnoozeMinutes');
      raw = snoozeMins != null ? snoozeMins * 60 : _defaultSnoozeSeconds;
    }
    return raw.clamp(minSnoozeSeconds, maxSnoozeSeconds);
  }

  /// Builds a validated, bounds-clamped [RoutinesCompanion] from one export map entry.
  ///
  /// Only known keys are read; any extra or legacy fields (for example
  /// MaxSnoozes, AutoSnoozeOnIgnore, IntervalHours) are ignored or folded into
  /// current columns. Absent fields receive the same defaults as a new routine.
  static RoutinesCompanion _routineCompanionFromMap(Map<String, Object?> r) {
    final trimmedName = _readString(r, 'Name')?.trim() ?? '';
    final String safeName;
    if (trimmedName.isEmpty) {
      safeName = _defaultName;
    } else if (trimmedName.length > maxNameLength) {
      safeName = trimmedName.substring(0, maxNameLength);
    } else {
      safeName = trimmedName;
    }

    final rawMaxTimes = _readInt(r, 'MaxTimesPerDay');
    final maxTimesPerDayEnabled =
        _readBool(r, 'MaxTimesPerDayEnabled') ?? ((rawMaxTimes ?? 0) > 0);
    final maxTimesPerDay = (rawMaxTimes ?? minMaxTimesPerDay).clamp(
      minMaxTimesPerDay,
      maxMaxTimesPerDay,
    );

    final dayStartSeconds = (_readInt(r, 'DayStartSeconds') ?? 0).clamp(
      minDayStartSeconds,
      maxDayStartSeconds,
    );

    final maskedWeekdays = (_readInt(r, 'EnabledWeekdays') ?? 0x7F) & 0x7F;
    final enabledWeekdays = maskedWeekdays == 0 ? 0x7F : maskedWeekdays;

    final rawCompensation = _readInt(r, 'DriftCompensationTypeCode');
    final compensationCode =
        (rawCompensation != null &&
            rawCompensation >= 0 &&
            rawCompensation < DriftCompensationTypeCodeEnum.values.length)
        ? rawCompensation
        : DriftCompensationTypeCodeEnum.ActualDismissal.index;

    final volume = (_readInt(r, 'Volume') ?? 50).clamp(minVolume, maxVolume);

    return RoutinesCompanion(
      Name: Value(safeName),
      IntervalSeconds: Value(_intervalSecondsFromMap(r)),
      SnoozeSeconds: Value(_snoozeSecondsFromMap(r)),
      MaxTimesPerDayEnabled: Value(maxTimesPerDayEnabled),
      MaxTimesPerDay: Value(maxTimesPerDay),
      DayStartSeconds: Value(dayStartSeconds),
      EnabledWeekdays: Value(enabledWeekdays),
      DriftCompensationTypeCode: Value(compensationCode),
      ShowPreview: Value(_readBool(r, 'ShowPreview') ?? true),
      Vibrate: Value(_readBool(r, 'Vibrate') ?? true),
      Volume: Value(volume),
      FadeIn: Value(_readBool(r, 'FadeIn') ?? false),
      AudioUri: Value(_readString(r, 'AudioUri')),
      IsActive: Value(_readBool(r, 'IsActive') ?? true),
    );
  }

  /// Imports routines from a validated export string.
  /// Every imported routine also gets a [RoutineStates] row seeded the same
  /// way a freshly created routine is scheduled (day start when the daily
  /// cap is on, otherwise one interval out). Returns the imported routine IDs.
  ///
  /// Older exports may omit newer fields; those use defaults. Extra or removed
  /// fields in the payload are ignored.
  static Future<List<int>> importFromBase64(
    RA_Database db,
    String exportString,
  ) async {
    final payload = decodeExportString(exportString);
    final rawRoutines = payload['routines'];
    if (rawRoutines is! List<Object?>) {
      throw const FormatException('Missing or invalid "routines" field');
    }

    final importedIds = <int>[];
    for (final item in rawRoutines) {
      if (item is! Map<Object?, Object?>) {
        throw const FormatException(
          'Invalid entry in "routines": each routine must be a JSON object',
        );
      }
      final r = Map<String, Object?>.from(item);
      final companion = _routineCompanionFromMap(r);
      final intervalSeconds = companion.IntervalSeconds.value;
      final nextTrigger = RA_DailyRingLimit.initialTriggerTime(
        now: DateTime.now(),
        interval: Duration(seconds: intervalSeconds),
        maxTimesPerDayEnabled: companion.MaxTimesPerDayEnabled.value,
        dayStartSeconds: companion.DayStartSeconds.value,
        enabledWeekdays: companion.EnabledWeekdays.present
            ? companion.EnabledWeekdays.value
            : 0x7F,
      );
      final routineId = await db.insertRoutineWithInitialState(
        routine: companion,
        nextTriggerTime: nextTrigger,
      );

      importedIds.add(routineId);
    }

    return importedIds;
  }
}
