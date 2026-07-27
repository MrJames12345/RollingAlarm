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
  static const int _currentVersion = 9;
  static const int _minSupportedVersion = 1;

  /// Matches the new-routine form default (2h 30m) when interval is absent.
  static const int _defaultIntervalSeconds = 9000;
  static const int _defaultSnoozeSeconds = 300;
  static const String _defaultName = 'Imported Routine';

  /// Exports all routines to a versioned base64 string.
  static Future<String> exportToBase64(RA_Database db) async {
    final routines = await (db.select(
      db.routines,
    )..where((r) => r.Deleted.equals(false))).get();

    final payload = {
      'version': _currentVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'routines': routines
          .map(
            (r) => {
              'Name': r.Name,
              'SnoozeSeconds': r.SnoozeSeconds,
              'IntervalSeconds': r.IntervalSeconds,
              'MaxTimesPerDayEnabled': r.MaxTimesPerDayEnabled,
              'MaxTimesPerDay': r.MaxTimesPerDay,
              'DayStartSeconds': r.DayStartSeconds,
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
  /// Returns the decoded payload map or throws on invalid input.
  static Map<String, dynamic> decodeExportString(String exportString) {
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
    if (payload['routines'] is! List) {
      throw const FormatException('Missing or invalid "routines" field');
    }
    return payload;
  }

  static Map<String, dynamic> _decodeJsonPayload(String base64Part) {
    try {
      final jsonString = utf8.decode(base64Decode(base64Part));
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic> || !decoded.containsKey('version')) {
        throw const FormatException(
          'Missing "version" field in export payload',
        );
      }
      return decoded;
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Invalid export payload: $e');
    }
  }

  /// Total interval seconds from a routine map.
  ///
  /// Version 4+ stores a single [IntervalSeconds] total. Older exports used
  /// hours + minutes + remainder seconds. Missing interval data uses
  /// [_defaultIntervalSeconds].
  static int _intervalSecondsFromMap(Map<String, dynamic> r) {
    final hours = r['IntervalHours'] as int?;
    final minutes = r['IntervalMinutes'] as int?;
    final seconds = r['IntervalSeconds'] as int?;
    if (hours == null && minutes == null && seconds == null) {
      return _defaultIntervalSeconds;
    }
    if (hours != null || minutes != null) {
      return ((hours ?? 0) * 3600) + ((minutes ?? 0) * 60) + (seconds ?? 0);
    }
    return seconds ?? _defaultIntervalSeconds;
  }

  /// Total snooze seconds from a routine map.
  ///
  /// Version 8+ stores [SnoozeSeconds]. Older exports used [SnoozeMinutes].
  /// Missing snooze data uses [_defaultSnoozeSeconds].
  static int _snoozeSecondsFromMap(Map<String, dynamic> r) {
    final snoozeSecs = r['SnoozeSeconds'] as int?;
    if (snoozeSecs != null) return snoozeSecs;
    final snoozeMins = r['SnoozeMinutes'] as int?;
    if (snoozeMins != null) return snoozeMins * 60;
    return _defaultSnoozeSeconds;
  }

  /// Builds a [RoutinesCompanion] from one export map entry.
  ///
  /// Only known keys are read; any extra or legacy fields (for example
  /// MaxSnoozes, AutoSnoozeOnIgnore, IntervalHours) are ignored or folded into
  /// current columns. Absent fields receive the same defaults as a new routine.
  static RoutinesCompanion _routineCompanionFromMap(Map<String, dynamic> r) {
    final name = (r['Name'] as String?)?.trim();
    final maxTimesPerDay = (r['MaxTimesPerDay'] as int?) ?? 0;
    return RoutinesCompanion(
      Name: Value((name == null || name.isEmpty) ? _defaultName : name),
      IntervalSeconds: Value(_intervalSecondsFromMap(r)),
      SnoozeSeconds: Value(_snoozeSecondsFromMap(r)),
      MaxTimesPerDayEnabled: Value(
        (r['MaxTimesPerDayEnabled'] as bool?) ?? (maxTimesPerDay > 0),
      ),
      MaxTimesPerDay: Value(maxTimesPerDay),
      DayStartSeconds: Value((r['DayStartSeconds'] as int?) ?? 0),
      DriftCompensationTypeCode: Value(
        (r['DriftCompensationTypeCode'] as int?) ??
            DriftCompensationTypeCodeEnum.ActualDismissal.index,
      ),
      ShowPreview: Value((r['ShowPreview'] as bool?) ?? true),
      Vibrate: Value((r['Vibrate'] as bool?) ?? true),
      Volume: Value(((r['Volume'] as int?) ?? 50).clamp(5, 100)),
      FadeIn: Value((r['FadeIn'] as bool?) ?? false),
      AudioUri: Value(r['AudioUri'] as String?),
      IsActive: Value((r['IsActive'] as bool?) ?? true),
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
    final routinesData = payload['routines'] as List;
    final importedIds = <int>[];

    for (final routineMap in routinesData) {
      final r = routineMap as Map<String, dynamic>;
      final companion = _routineCompanionFromMap(r);
      final intervalSeconds = companion.IntervalSeconds.value;
      final nextTrigger = RA_DailyRingLimit.initialTriggerTime(
        now: DateTime.now(),
        interval: Duration(seconds: intervalSeconds),
        maxTimesPerDayEnabled: companion.MaxTimesPerDayEnabled.value,
        dayStartSeconds: companion.DayStartSeconds.value,
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
