import 'dart:convert';
import 'dart:ui';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';
import 'package:rolling_alarm/services/daily_ring_limit.dart';
import 'package:rolling_alarm/services/swing_roster.dart';
import 'package:rolling_alarm/services/weekday_schedule.dart';
import 'package:rolling_alarm/utils.dart';
import 'package:share_plus/share_plus.dart';

/// Versioned JSON-to-base64 export/import service.
/// Format: `RA1:` followed by base64-encoded JSON.
class RA_ExportService {
  RA_ExportService._();

  static const String _versionPrefix = 'RA1:';
  static const int _currentVersion = 11;
  static const int _minSupportedVersion = 1;
  static const String presetShareBaseUrl =
      'https://casellaweb.com.au/rolling-alarm';

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
  static const int minCycleDays = 0;
  static const int maxCycleDays = RA_SwingRosterSchedule.maxCycleDays;

  /// Safe calendar epoch-day bounds (1970-01-01 .. year 2243) so crafted
  /// imports can never overflow [DateTime.fromMillisecondsSinceEpoch].
  static const int minAnchorEpochDay = 0;
  static const int maxAnchorEpochDay = 100000;
  static const int maxNameLength = 255;

  /// Matches the new-routine form default (2h 30m) when interval is absent.
  static const int _defaultIntervalSeconds = 9000;
  static const int _defaultSnoozeSeconds = 300;
  static const String _defaultName = 'Imported Routine';

  static final RegExp _urlPattern = RegExp(
    r'https?://[^\s<>"]+',
    caseSensitive: false,
  );
  static final RegExp _presetQueryPattern = RegExp(
    r'[?&]preset=((?:RA1(?::|%3A))[^&#\r\n"<>]+)',
    caseSensitive: false,
  );
  static final RegExp _rawOrEncodedTokenPattern = RegExp(
    r'RA1(?::|%3A)[A-Za-z0-9%+/=_-]+',
    caseSensitive: false,
  );
  static final RegExp _validBase64SegmentPattern = RegExp(
    r'^[A-Za-z0-9%+/=_-]+$',
  );
  static final RegExp _validBase64OnlyPattern = RegExp(
    r'^[A-Za-z0-9+/=_-]+$',
  );
  static final RegExp _whitespacePattern = RegExp(r'\s');

  @visibleForTesting
  static Future<void> Function(ShareParams params)? debugShareOverride;

  @visibleForTesting
  static void resetForTesting() {
    debugShareOverride = null;
  }

  static Map<String, Object?> _routineToMap(
    RoutineModel r, {
    bool forceActive = false,
  }) {
    final hasSwing = RA_SwingRosterSchedule.isActive(
      cycleOnDays: r.CycleOnDays,
      cycleOffDays: r.CycleOffDays,
      cycleAnchorEpochDay: r.CycleAnchorEpochDay,
    );
    return <String, Object?>{
      'Name': r.Name,
      'SnoozeSeconds': r.SnoozeSeconds,
      'IntervalSeconds': r.IntervalSeconds,
      'MaxTimesPerDayEnabled': r.MaxTimesPerDayEnabled,
      'MaxTimesPerDay': r.MaxTimesPerDay,
      'DayStartSeconds': r.DayStartSeconds,
      'EnabledWeekdays': r.EnabledWeekdays,
      'CycleOnDays': r.CycleOnDays,
      'CycleOffDays': r.CycleOffDays,
      'CycleAnchorEpochDay': r.CycleAnchorEpochDay,
      if (hasSwing)
        'SwingSchedule': RA_SwingRosterSchedule.exportLabel(
          cycleOnDays: r.CycleOnDays,
          cycleOffDays: r.CycleOffDays,
        ),
      'DriftCompensationTypeCode': r.DriftCompensationTypeCode,
      'ShowPreview': r.ShowPreview,
      'Vibrate': r.Vibrate,
      'Volume': r.Volume,
      'FadeIn': r.FadeIn,
      'AudioUri': r.AudioUri,
      'IsActive': forceActive ? true : r.IsActive,
    };
  }

  static String _encodeRoutines(
    List<RoutineModel> routines, {
    DateTime? exportedAt,
    bool forceActive = false,
  }) {
    final payload = <String, Object?>{
      'version': _currentVersion,
      'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
      'routines': routines
          .map((r) => _routineToMap(r, forceActive: forceActive))
          .toList(),
    };
    final jsonString = jsonEncode(payload);
    final base64String = base64Encode(utf8.encode(jsonString));
    return '$_versionPrefix$base64String';
  }

  /// Exports all non-deleted routines to a versioned base64 string.
  static Future<String> exportToBase64(RA_Database db) async {
    final routines = await (db.select(
      db.routines,
    )..where((r) => r.Deleted.equals(false))).get();
    return _encodeRoutines(routines);
  }

  /// Exports a single [routine] as a compact `RA1:<base64>` preset string.
  ///
  /// 100% free — designed for sharing medication, ADHD, and FIFO routines.
  /// Shared presets always export with `IsActive: true` so recipients get a
  /// live schedule even if the sender temporarily paused their own routine.
  static String exportSingleRoutine(
    RoutineModel routine, {
    DateTime? exportedAt,
  }) {
    return _encodeRoutines([routine], exportedAt: exportedAt, forceActive: true);
  }

  /// Builds a clickable `https://casellaweb.com.au/rolling-alarm?preset=RA1:...`
  /// share URL for [routine].
  static String buildShareablePresetUrl(
    RoutineModel routine, {
    String? preEncodedCode,
    DateTime? exportedAt,
  }) {
    final code =
        preEncodedCode ?? exportSingleRoutine(routine, exportedAt: exportedAt);
    final base64Part = code.startsWith(_versionPrefix)
        ? code.substring(_versionPrefix.length)
        : code;
    return '$presetShareBaseUrl?preset=$_versionPrefix${Uri.encodeQueryComponent(base64Part)}';
  }

  /// Produces a clean, human-readable share message containing a schedule
  /// summary, clickable web preview URL, and raw `RA1:...` preset code.
  static String buildShareablePresetMessage(
    RoutineModel routine, {
    DateTime? exportedAt,
  }) {
    final code = exportSingleRoutine(routine, exportedAt: exportedAt);
    final url = buildShareablePresetUrl(routine, preEncodedCode: code);
    final intervalLabel = RA_Utils.formatInterval(routine.IntervalSeconds);
    final dayStart = RA_DailyRingLimit.normalizeDayStartSeconds(
      routine.DayStartSeconds,
    );
    final dayStartLabel = RA_Utils.formatTime(
      DateTime(2000, 1, 1).add(Duration(seconds: dayStart)),
    );

    final summaryParts = <String>['Every $intervalLabel'];
    if (routine.MaxTimesPerDayEnabled) {
      summaryParts.add('${routine.MaxTimesPerDay}/day');
    }
    if (routine.MaxTimesPerDayEnabled ||
        !RA_WeekdaySchedule.isEveryDay(routine.EnabledWeekdays) ||
        RA_SwingRosterSchedule.isActive(
          cycleOnDays: routine.CycleOnDays,
          cycleOffDays: routine.CycleOffDays,
          cycleAnchorEpochDay: routine.CycleAnchorEpochDay,
        )) {
      summaryParts.add('Starts $dayStartLabel');
    }
    if (!RA_WeekdaySchedule.isEveryDay(routine.EnabledWeekdays)) {
      summaryParts.add(RA_WeekdaySchedule.summaryLabel(routine.EnabledWeekdays));
    }
    if (RA_SwingRosterSchedule.isActive(
      cycleOnDays: routine.CycleOnDays,
      cycleOffDays: routine.CycleOffDays,
      cycleAnchorEpochDay: routine.CycleAnchorEpochDay,
    )) {
      summaryParts.add(
        RA_SwingRosterSchedule.exportLabel(
          cycleOnDays: routine.CycleOnDays,
          cycleOffDays: routine.CycleOffDays,
        ),
      );
    }

    return 'Rolling Alarm Routine: ${routine.Name}\n'
        '${summaryParts.join(' · ')}\n\n'
        'Preview & import:\n'
        '$url\n\n'
        'Or paste this code into Rolling Alarm -> Settings -> Import Routines:\n'
        '$code';
  }

  /// Opens the native share sheet with a free single-routine preset message.
  static Future<void> shareRoutinePreset(
    RoutineModel routine, {
    Rect? sharePositionOrigin,
  }) async {
    final message = buildShareablePresetMessage(routine);
    final params = ShareParams(
      text: message,
      subject: '${routine.Name} — Rolling Alarm Routine',
      sharePositionOrigin: sharePositionOrigin,
    );
    try {
      final override = debugShareOverride;
      if (override != null) {
        await override(params);
        return;
      }
      await SharePlus.instance.share(params);
    } catch (_) {
      // Ignore share-sheet failures in headless / test environments.
    }
  }

  /// Extracts a canonical `RA1:...` token from:
  /// - a raw `RA1:...` string (standard, URL-safe, percent-encoded, or line-wrapped),
  /// - a `https://casellaweb.com.au/rolling-alarm?preset=RA1:...` URL (with or
  ///   without scheme, encoded, unencoded, or space-munged `+`), or
  /// - multi-line shared messages / Reddit comments containing either form.
  ///
  /// When multiple candidates exist (e.g. a truncated link followed by a raw
  /// `RA1:` block), returns the first candidate that decodes as valid `RA1:`
  /// JSON; otherwise returns the first syntactic candidate so callers report a
  /// descriptive [FormatException]. Returns `null` when no `RA1:` token exists.
  static String? extractRa1Token(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) return null;

    // Direct single-token input starting with RA1: stays strict against invalid
    // garbage characters while still normalizing percent-encoding (`%2B`/`%3D`)
    // and URL-safe base64 (`-`/`_` / unpadded).
    if (trimmed.startsWith(_versionPrefix) &&
        !_whitespacePattern.hasMatch(trimmed)) {
      final directPayload = trimmed.substring(_versionPrefix.length);
      if (directPayload.contains('%')) {
        try {
          final decoded = Uri.decodeQueryComponent(directPayload);
          final canonical = _canonicalizeExtractedToken('$_versionPrefix$decoded');
          if (canonical != null) return canonical;
        } catch (_) {}
        return trimmed;
      }
      if (_validBase64OnlyPattern.hasMatch(directPayload)) {
        final canonical = _canonicalizeExtractedToken(trimmed);
        if (canonical != null) return canonical;
      }
      return trimmed;
    }

    final candidates = <String>[];
    final seen = <String>{};

    void addCandidate(String? candidate) {
      if (candidate == null || candidate.isEmpty) return;
      if (seen.add(candidate)) {
        candidates.add(candidate);
      }
    }

    // 1. Direct line-wrapped RA1: block (e.g. email/SMS wrapped base64).
    if (trimmed.startsWith(_versionPrefix)) {
      final compact = trimmed.replaceAll(_whitespacePattern, '');
      if (_validBase64OnlyPattern.hasMatch(
        compact.substring(_versionPrefix.length),
      )) {
        addCandidate(_canonicalizeExtractedToken(compact));
      }
    }

    // 2. Full URLs carrying a `preset` query parameter.
    for (final match in _urlPattern.allMatches(trimmed)) {
      final rawUrl = _stripTrailingUrlPunctuation(match.group(0) ?? '');
      final uri = Uri.tryParse(rawUrl);
      if (uri == null) continue;
      final preset = _queryParamIgnoreCase(uri, 'preset');
      if (preset != null) {
        addCandidate(_decodeAndCanonicalize(preset));
      }
    }

    // 3. `?preset=RA1:...` / `&preset=RA1%3A...` spans (covers scheme-less URLs
    //    AND unencoded `+` converted into spaces inside the query value).
    for (final match in _presetQueryPattern.allMatches(trimmed)) {
      final rawSpan = _stripTrailingUrlPunctuation(
        (match.group(1) ?? '').trim(),
      );
      if (rawSpan.isEmpty) continue;
      final parts = rawSpan.split(RegExp(r' +'));
      // Take the longest contiguous prefix of valid base64/percent tokens.
      var validCount = 0;
      for (var i = 0; i < parts.length; i++) {
        final part = _stripTrailingUrlPunctuation(parts[i]);
        final check = i == 0
            ? part.replaceFirst(
                RegExp(r'^RA1(?::|%3A)', caseSensitive: false),
                '',
              )
            : part;
        if (check.isEmpty || !_validBase64SegmentPattern.hasMatch(check)) {
          break;
        }
        validCount = i + 1;
      }
      for (var len = validCount; len >= 1; len--) {
        final joined = <String>[
          for (var i = 0; i < len; i++)
            i == len - 1 ? _stripTrailingUrlPunctuation(parts[i]) : parts[i],
        ].join('+');
        addCandidate(_decodeAndCanonicalize(joined));
      }
    }

    // 4. Raw or percent-encoded `RA1:...` / `RA1%3A...` tokens anywhere in text.
    for (final match in _rawOrEncodedTokenPattern.allMatches(trimmed)) {
      final token = _stripTrailingUrlPunctuation(match.group(0) ?? '');
      addCandidate(_decodeAndCanonicalize(token));
    }

    if (candidates.isEmpty) return null;

    // Prefer the first candidate that actually decodes as valid RA1 JSON so a
    // truncated link earlier in a message does not mask an intact RA1: block.
    for (final candidate in candidates) {
      if (_isValidEncodedPayload(candidate)) {
        return candidate;
      }
    }
    return candidates.first;
  }

  static bool _isValidEncodedPayload(String token) {
    if (!token.startsWith(_versionPrefix)) return false;
    if (token.length > maxPayloadBytes) return false;
    try {
      final payload = _decodeJsonPayload(token.substring(_versionPrefix.length));
      final version = payload['version'];
      final routines = payload['routines'];
      return version is int &&
          version >= _minSupportedVersion &&
          version <= _currentVersion &&
          routines is List<Object?>;
    } catch (_) {
      return false;
    }
  }

  static String? _decodeAndCanonicalize(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return null;
    if (value.contains('%')) {
      try {
        value = Uri.decodeQueryComponent(value);
      } catch (_) {}
    }
    return _canonicalizeExtractedToken(value);
  }

  /// Returns a validated canonical `RA1:...` token if [rawInput] contains a
  /// decodable Rolling Alarm preset, or `null` otherwise (used for clipboard
  /// auto-detect in `RA_showImportDialog`).
  static String? tryExtractValidPreset(String? rawInput) {
    if (rawInput == null || rawInput.trim().isEmpty) return null;
    try {
      final token = extractRa1Token(rawInput);
      if (token == null) return null;
      decodeExportString(token);
      return token;
    } catch (_) {
      return null;
    }
  }

  static String _stripTrailingUrlPunctuation(String url) {
    var end = url.length;
    while (end > 0) {
      final ch = url[end - 1];
      if (ch == ')' || ch == ']' || ch == '>' || ch == '.' || ch == ',' || ch == ';') {
        end--;
      } else {
        break;
      }
    }
    return url.substring(0, end);
  }

  static String? _queryParamIgnoreCase(Uri uri, String key) {
    final direct = uri.queryParameters[key];
    if (direct != null) return direct;
    final lower = key.toLowerCase();
    for (final entry in uri.queryParameters.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  static String? _canonicalizeExtractedToken(String candidate) {
    final cleaned = candidate.trim();
    if (!cleaned.startsWith(_versionPrefix)) return null;
    // URL query decoding converts unencoded '+' to spaces; restore base64 chars.
    var b64 = cleaned
        .substring(_versionPrefix.length)
        .replaceAll(' ', '+')
        .replaceAll('-', '+')
        .replaceAll('_', '/');
    b64 = b64.replaceAll(_whitespacePattern, '');
    if (b64.isEmpty) return null;
    final rem = b64.length % 4;
    if (rem == 2) {
      b64 = '$b64==';
    } else if (rem == 3) {
      b64 = '$b64=';
    }
    return '$_versionPrefix$b64';
  }

  /// Validates and decodes an `RA1:` export string, preset URL, or message
  /// containing an embedded `RA1:` token.
  /// Returns the decoded payload map or throws [FormatException] on invalid input.
  static Map<String, Object?> decodeExportString(String exportString) {
    if (exportString.length > maxPayloadBytes ||
        utf8.encode(exportString).length > maxPayloadBytes) {
      throw const FormatException(
        'Export payload exceeds maximum allowed size of 512 KB',
      );
    }

    final token = extractRa1Token(exportString);
    if (token == null || !token.startsWith(_versionPrefix)) {
      throw const FormatException(
        'Invalid export format: missing version prefix "$_versionPrefix"',
      );
    }

    if (token.length > maxPayloadBytes ||
        utf8.encode(token).length > maxPayloadBytes) {
      throw const FormatException(
        'Export payload exceeds maximum allowed size of 512 KB',
      );
    }

    final payload = _decodeJsonPayload(
      token.substring(_versionPrefix.length),
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

    final rawCycleOn = (_readInt(r, 'CycleOnDays') ?? 0).clamp(
      minCycleDays,
      maxCycleDays,
    );
    final rawCycleOff = (_readInt(r, 'CycleOffDays') ?? 0).clamp(
      minCycleDays,
      maxCycleDays,
    );
    final bool hasCompleteSwing = rawCycleOn > 0 && rawCycleOff > 0;
    final int cycleOnDays = hasCompleteSwing ? rawCycleOn : 0;
    final int cycleOffDays = hasCompleteSwing ? rawCycleOff : 0;
    final rawAnchor = _readInt(r, 'CycleAnchorEpochDay');
    final int? cycleAnchorEpochDay;
    if (hasCompleteSwing) {
      final candidateAnchor =
          rawAnchor ?? RA_SwingRosterSchedule.localEpochDay(DateTime.now());
      cycleAnchorEpochDay = candidateAnchor.clamp(
        minAnchorEpochDay,
        maxAnchorEpochDay,
      );
    } else {
      cycleAnchorEpochDay = null;
    }

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
      CycleOnDays: Value(cycleOnDays),
      CycleOffDays: Value(cycleOffDays),
      CycleAnchorEpochDay: Value(cycleAnchorEpochDay),
      DriftCompensationTypeCode: Value(compensationCode),
      ShowPreview: Value(_readBool(r, 'ShowPreview') ?? true),
      Vibrate: Value(_readBool(r, 'Vibrate') ?? true),
      Volume: Value(volume),
      FadeIn: Value(_readBool(r, 'FadeIn') ?? false),
      AudioUri: Value(_readString(r, 'AudioUri')),
      IsActive: Value(_readBool(r, 'IsActive') ?? true),
    );
  }

  /// Imports routines from a validated export string, preset URL, or text
  /// snippet containing an `RA1:` token.
  /// Every imported routine also gets a [RoutineStates] row seeded the same
  /// way a freshly created routine is scheduled (day start when the daily
  /// cap is on, otherwise one interval out, deferred to active swing & weekday).
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
      final now = DateTime.now();
      final nextTrigger = RA_DailyRingLimit.initialTriggerTime(
        now: now,
        interval: Duration(seconds: intervalSeconds),
        maxTimesPerDayEnabled: companion.MaxTimesPerDayEnabled.value,
        dayStartSeconds: companion.DayStartSeconds.value,
        enabledWeekdays: companion.EnabledWeekdays.present
            ? companion.EnabledWeekdays.value
            : 0x7F,
        cycleOnDays: companion.CycleOnDays.present
            ? companion.CycleOnDays.value
            : 0,
        cycleOffDays: companion.CycleOffDays.present
            ? companion.CycleOffDays.value
            : 0,
        cycleAnchorEpochDay: companion.CycleAnchorEpochDay.present
            ? companion.CycleAnchorEpochDay.value
            : null,
      );
      final routineId = await db.insertRoutineWithInitialState(
        routine: companion,
        nextTriggerTime: nextTrigger,
      );
      final isActive = companion.IsActive.present
          ? companion.IsActive.value
          : true;
      if (!isActive) {
        await db.updateRoutineState(
          routineId,
          RoutineStatesCompanion(PausedAt: Value(now)),
        );
      }

      importedIds.add(routineId);
    }

    return importedIds;
  }
}
