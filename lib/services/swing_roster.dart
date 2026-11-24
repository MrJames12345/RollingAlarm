import 'package:rolling_alarm/services/daily_ring_limit.dart';
import 'package:rolling_alarm/services/weekday_schedule.dart';
import 'package:rolling_alarm/utils.dart';

/// Named preset chip for FIFO & nursing swing-roster cycles.
class RA_SwingRosterPreset {
  final String id;
  final String label;
  final int onDays;
  final int offDays;
  final bool requiresPro;

  const RA_SwingRosterPreset({
    required this.id,
    required this.label,
    required this.onDays,
    required this.offDays,
    required this.requiresPro,
  });
}

/// Snapshot of a routine's current position in an active swing-roster cycle.
class RA_SwingRosterStatus {
  final bool isOnSwing;
  final int dayNumber;
  final int cycleOnDays;
  final int cycleOffDays;
  final DateTime? nextOnSwingStart;

  const RA_SwingRosterStatus({
    required this.isOnSwing,
    required this.dayNumber,
    required this.cycleOnDays,
    required this.cycleOffDays,
    this.nextOnSwingStart,
  });

  /// Compact ratio string, e.g. `"8/6"` or `"14/7"`.
  String get ratioLabel => '$cycleOnDays/$cycleOffDays';

  /// Crisp card badge text, e.g.:
  /// - `"8/6 Swing · Day 3 of 8 ON"`
  /// - `"R&R Off-Swing · Starts Tue 6:00 AM"`
  String get badgeLabel {
    if (isOnSwing) {
      return '$ratioLabel Swing · Day $dayNumber of $cycleOnDays ON';
    }
    final next = nextOnSwingStart;
    if (next != null) {
      return 'R&R Off-Swing · Starts ${RA_Utils.formatWeekdayShort(next)} ${RA_Utils.formatTime(next)}';
    }
    return 'R&R Off-Swing · Day $dayNumber of $cycleOffDays OFF';
  }
}

/// Pure, deterministic, DST-safe swing-roster schedule helpers for N-days-ON /
/// M-days-OFF FIFO and rotating shift cycles.
///
/// Respects `DayStartSeconds` logical day boundaries (matching
/// [RA_DailyRingLimit.periodStart]) and composes cleanly with
/// [RA_WeekdaySchedule] bitmasks.
class RA_SwingRosterSchedule {
  RA_SwingRosterSchedule._();

  static const int minCycleDays = 1;
  static const int maxCycleDays = 60;

  /// Curated 1-tap swing roster chips shown in [RoutineEditPage].
  /// `8/6` and `4 On / 4 Off` are free; `2/1` and `2/2` (and custom N/M)
  /// require Rolling Alarm Pro.
  static const List<RA_SwingRosterPreset> presets = [
    RA_SwingRosterPreset(
      id: '8_6',
      label: '8/6',
      onDays: 8,
      offDays: 6,
      requiresPro: false,
    ),
    RA_SwingRosterPreset(
      id: '2_1',
      label: '2/1 (14/7)',
      onDays: 14,
      offDays: 7,
      requiresPro: true,
    ),
    RA_SwingRosterPreset(
      id: '2_2',
      label: '2/2 (14/14)',
      onDays: 14,
      offDays: 14,
      requiresPro: true,
    ),
    RA_SwingRosterPreset(
      id: '4_4',
      label: '4 On / 4 Off',
      onDays: 4,
      offDays: 4,
      requiresPro: false,
    ),
  ];

  /// Whether a custom `onDays` / `offDays` combination is free without Pro.
  static bool isFreeCyclePair({
    required int cycleOnDays,
    required int cycleOffDays,
  }) {
    for (final preset in presets) {
      if (!preset.requiresPro &&
          preset.onDays == cycleOnDays &&
          preset.offDays == cycleOffDays) {
        return true;
      }
    }
    return false;
  }

  /// Whether a swing-roster cycle is active for the given column values.
  static bool isActive({
    required int cycleOnDays,
    required int cycleOffDays,
    required int? cycleAnchorEpochDay,
  }) => cycleOnDays > 0 && cycleOffDays > 0 && cycleAnchorEpochDay != null;

  /// DST-safe local calendar day index for [dateTime] (`1970-01-01 == 0`).
  ///
  /// Projects local `(year, month, day)` into UTC midnight so spring-forward
  /// and fall-back transitions never shift the day count by +/- 1.
  static int localEpochDay(DateTime dateTime) {
    final local = dateTime.toLocal();
    return DateTime.utc(local.year, local.month, local.day)
            .millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
  }

  /// Reconstructs local midnight `DateTime(y, m, d)` from [epochDay].
  static DateTime dateFromEpochDay(int epochDay) {
    final utc = DateTime.fromMillisecondsSinceEpoch(
      epochDay * Duration.millisecondsPerDay,
      isUtc: true,
    );
    return DateTime(utc.year, utc.month, utc.day);
  }

  /// Local epoch day of the logical day containing [dateTime] under
  /// [dayStartSeconds] (matching [RA_DailyRingLimit.periodStart]).
  static int logicalEpochDay(DateTime dateTime, {int dayStartSeconds = 0}) {
    final period = RA_DailyRingLimit.periodStart(dateTime, dayStartSeconds);
    return localEpochDay(period);
  }

  /// Position `0 .. (cycleOnDays + cycleOffDays - 1)` within the cycle for
  /// [epochDay]. Dart's `%` is Euclidean (always non-negative for positive
  /// divisors), so anchors in the future wrap cleanly as well.
  static int dayIndexInCycle({
    required int epochDay,
    required int cycleOnDays,
    required int cycleOffDays,
    required int cycleAnchorEpochDay,
  }) {
    final cycleLength = cycleOnDays + cycleOffDays;
    return (epochDay - cycleAnchorEpochDay) % cycleLength;
  }

  /// Whether [epochDay] falls in the ON window `[0, cycleOnDays)` modulo
  /// `(cycleOnDays + cycleOffDays)`. Returns `true` when swing is disabled.
  static bool isEpochDayOnSwing({
    required int epochDay,
    required int cycleOnDays,
    required int cycleOffDays,
    required int? cycleAnchorEpochDay,
  }) {
    if (!isActive(
      cycleOnDays: cycleOnDays,
      cycleOffDays: cycleOffDays,
      cycleAnchorEpochDay: cycleAnchorEpochDay,
    )) {
      return true;
    }
    final pos = dayIndexInCycle(
      epochDay: epochDay,
      cycleOnDays: cycleOnDays,
      cycleOffDays: cycleOffDays,
      cycleAnchorEpochDay: cycleAnchorEpochDay!,
    );
    return pos < cycleOnDays;
  }

  /// Whether [dateTime]'s logical day (respecting [dayStartSeconds]) falls in
  /// an ON-swing day. Returns `true` when swing is disabled.
  static bool isOnSwing(
    DateTime dateTime, {
    required int cycleOnDays,
    required int cycleOffDays,
    required int? cycleAnchorEpochDay,
    int dayStartSeconds = 0,
  }) {
    if (!isActive(
      cycleOnDays: cycleOnDays,
      cycleOffDays: cycleOffDays,
      cycleAnchorEpochDay: cycleAnchorEpochDay,
    )) {
      return true;
    }
    final epochDay = logicalEpochDay(
      dateTime,
      dayStartSeconds: dayStartSeconds,
    );
    return isEpochDayOnSwing(
      epochDay: epochDay,
      cycleOnDays: cycleOnDays,
      cycleOffDays: cycleOffDays,
      cycleAnchorEpochDay: cycleAnchorEpochDay,
    );
  }

  /// Whether [dateTime] is eligible to ring under BOTH [enabledWeekdays] and
  /// the optional swing roster cycle.
  ///
  /// When the swing cycle is disabled, delegates strictly to
  /// [RA_WeekdaySchedule.isDateEnabled] for 100% backwards compatibility.
  static bool isDateActive(
    DateTime dateTime, {
    required int enabledWeekdays,
    int dayStartSeconds = 0,
    int cycleOnDays = 0,
    int cycleOffDays = 0,
    int? cycleAnchorEpochDay,
  }) {
    if (!isActive(
      cycleOnDays: cycleOnDays,
      cycleOffDays: cycleOffDays,
      cycleAnchorEpochDay: cycleAnchorEpochDay,
    )) {
      return RA_WeekdaySchedule.isDateEnabled(enabledWeekdays, dateTime);
    }

    final logicalStart = RA_DailyRingLimit.periodStart(
      dateTime,
      dayStartSeconds,
    );
    final epochDay = localEpochDay(logicalStart);
    if (!isEpochDayOnSwing(
      epochDay: epochDay,
      cycleOnDays: cycleOnDays,
      cycleOffDays: cycleOffDays,
      cycleAnchorEpochDay: cycleAnchorEpochDay,
    )) {
      return false;
    }
    return RA_WeekdaySchedule.isDateEnabled(enabledWeekdays, logicalStart);
  }

  /// Defers [proposed] to the first logical day that is **both** an ON-swing
  /// day **and** an enabled weekday, landing cleanly at [dayStartSeconds].
  ///
  /// When the swing cycle is disabled, delegates strictly to
  /// [RA_WeekdaySchedule.deferToEnabledDay].
  static DateTime deferToActiveDay(
    DateTime proposed, {
    required int enabledWeekdays,
    int dayStartSeconds = 0,
    int cycleOnDays = 0,
    int cycleOffDays = 0,
    int? cycleAnchorEpochDay,
  }) {
    if (!isActive(
      cycleOnDays: cycleOnDays,
      cycleOffDays: cycleOffDays,
      cycleAnchorEpochDay: cycleAnchorEpochDay,
    )) {
      return RA_WeekdaySchedule.deferToEnabledDay(
        proposed,
        enabledWeekdays,
        dayStartSeconds: dayStartSeconds,
      );
    }

    final effectiveMask = RA_WeekdaySchedule.effectiveMask(enabledWeekdays);
    final offset = RA_DailyRingLimit.normalizeDayStartSeconds(dayStartSeconds);
    final hour = offset ~/ 3600;
    final minute = (offset % 3600) ~/ 60;
    final second = offset % 60;

    final logicalStart = RA_DailyRingLimit.periodStart(proposed, offset);
    final startEpochDay = localEpochDay(logicalStart);
    final anchor = cycleAnchorEpochDay!;

    if (isEpochDayOnSwing(
          epochDay: startEpochDay,
          cycleOnDays: cycleOnDays,
          cycleOffDays: cycleOffDays,
          cycleAnchorEpochDay: anchor,
        ) &&
        RA_WeekdaySchedule.isDateEnabled(effectiveMask, logicalStart)) {
      return proposed;
    }

    // Walk day-by-day up to the full joint period (cycleLength * 7, which is
    // always >= cycleLength + 7 for any valid cycle) so any intersecting day is
    // guaranteed to be found.
    final cycleLength = cycleOnDays + cycleOffDays;
    final maxSteps = cycleLength * 7;
    DateTime? firstOnSwingFallback;

    for (var i = 1; i <= maxSteps; i++) {
      final candidateEpoch = startEpochDay + i;
      if (!isEpochDayOnSwing(
        epochDay: candidateEpoch,
        cycleOnDays: cycleOnDays,
        cycleOffDays: cycleOffDays,
        cycleAnchorEpochDay: anchor,
      )) {
        continue;
      }
      final day = dateFromEpochDay(candidateEpoch);
      final landing = DateTime(day.year, day.month, day.day, hour, minute, second);
      firstOnSwingFallback ??= landing;
      if (RA_WeekdaySchedule.isDateEnabled(effectiveMask, day)) {
        return landing;
      }
    }

    return firstOnSwingFallback ?? proposed;
  }

  /// Whether at least one calendar day in the joint `(cycleOnDays + cycleOffDays) * 7`
  /// period is **both** an ON-swing day **and** an enabled weekday.
  ///
  /// Returns `true` when the swing cycle is disabled. Returns `false` for
  /// impossible configurations such as `3 On / 4 Off` (Mon–Wed ON) paired with
  /// `Thu–Fri` only weekdays.
  static bool hasIntersectingActiveDay({
    required int cycleOnDays,
    required int cycleOffDays,
    required int? cycleAnchorEpochDay,
    required int enabledWeekdays,
  }) {
    if (!isActive(
      cycleOnDays: cycleOnDays,
      cycleOffDays: cycleOffDays,
      cycleAnchorEpochDay: cycleAnchorEpochDay,
    )) {
      return true;
    }
    final effectiveMask = RA_WeekdaySchedule.effectiveMask(enabledWeekdays);
    if (effectiveMask == RA_WeekdaySchedule.allDaysMask) return true;

    final anchor = cycleAnchorEpochDay!;
    final cycleLength = cycleOnDays + cycleOffDays;
    final maxSteps = cycleLength * 7;
    for (var i = 0; i < maxSteps; i++) {
      final candidateEpoch = anchor + i;
      if (!isEpochDayOnSwing(
        epochDay: candidateEpoch,
        cycleOnDays: cycleOnDays,
        cycleOffDays: cycleOffDays,
        cycleAnchorEpochDay: anchor,
      )) {
        continue;
      }
      final day = dateFromEpochDay(candidateEpoch);
      if (RA_WeekdaySchedule.isDateEnabled(effectiveMask, day)) {
        return true;
      }
    }
    return false;
  }

  /// Computes the live UI badge status for [now], or `null` when disabled.
  static RA_SwingRosterStatus? statusAt({
    required DateTime now,
    required int cycleOnDays,
    required int cycleOffDays,
    required int? cycleAnchorEpochDay,
    int dayStartSeconds = 0,
    int enabledWeekdays = RA_WeekdaySchedule.allDaysMask,
  }) {
    if (!isActive(
      cycleOnDays: cycleOnDays,
      cycleOffDays: cycleOffDays,
      cycleAnchorEpochDay: cycleAnchorEpochDay,
    )) {
      return null;
    }

    final anchor = cycleAnchorEpochDay!;
    final epochDay = logicalEpochDay(now, dayStartSeconds: dayStartSeconds);
    final pos = dayIndexInCycle(
      epochDay: epochDay,
      cycleOnDays: cycleOnDays,
      cycleOffDays: cycleOffDays,
      cycleAnchorEpochDay: anchor,
    );

    if (pos < cycleOnDays) {
      return RA_SwingRosterStatus(
        isOnSwing: true,
        dayNumber: pos + 1,
        cycleOnDays: cycleOnDays,
        cycleOffDays: cycleOffDays,
      );
    }

    final hasMatch = hasIntersectingActiveDay(
      cycleOnDays: cycleOnDays,
      cycleOffDays: cycleOffDays,
      cycleAnchorEpochDay: anchor,
      enabledWeekdays: enabledWeekdays,
    );
    final nextStart = hasMatch
        ? deferToActiveDay(
            now,
            enabledWeekdays: enabledWeekdays,
            dayStartSeconds: dayStartSeconds,
            cycleOnDays: cycleOnDays,
            cycleOffDays: cycleOffDays,
            cycleAnchorEpochDay: anchor,
          )
        : null;
    return RA_SwingRosterStatus(
      isOnSwing: false,
      dayNumber: (pos - cycleOnDays) + 1,
      cycleOnDays: cycleOnDays,
      cycleOffDays: cycleOffDays,
      nextOnSwingStart: nextStart,
    );
  }

  /// Compact summary label for `RoutineSummaryPage`, e.g. `"8d On / 6d Off"` or `"Off"`.
  static String summaryLabel({
    required int cycleOnDays,
    required int cycleOffDays,
    required int? cycleAnchorEpochDay,
  }) {
    if (!isActive(
      cycleOnDays: cycleOnDays,
      cycleOffDays: cycleOffDays,
      cycleAnchorEpochDay: cycleAnchorEpochDay,
    )) {
      return 'Off';
    }
    return '${cycleOnDays}d On / ${cycleOffDays}d Off';
  }

  /// Human-readable label exported under `SwingSchedule` in `RA1:` presets
  /// (consumed by `casellaweb.com.au/rolling-alarm?preset=RA1:...`).
  static String exportLabel({
    required int cycleOnDays,
    required int cycleOffDays,
  }) => '$cycleOnDays/$cycleOffDays Swing (${cycleOnDays}d On / ${cycleOffDays}d Off)';
}
