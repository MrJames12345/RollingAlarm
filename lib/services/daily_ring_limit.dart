import 'package:rolling_alarm/services/weekday_schedule.dart';

/// Pure helpers for the per-day ring cap.
///
/// A "day" starts at [dayStartSeconds] past local midnight (not necessarily
/// 00:00) and runs until the next occurrence of that time.
class RA_DailyRingLimit {
  RA_DailyRingLimit._();

  static const int secondsPerDay = 24 * 60 * 60;

  /// Clamps [dayStartSeconds] into a valid time-of-day offset.
  static int normalizeDayStartSeconds(int dayStartSeconds) =>
      dayStartSeconds.clamp(0, secondsPerDay - 1);

  /// Start of the current day period containing [now].
  static DateTime periodStart(DateTime now, int dayStartSeconds) {
    final offset = Duration(seconds: normalizeDayStartSeconds(dayStartSeconds));
    final todayStart = DateTime(now.year, now.month, now.day).add(offset);
    if (now.isBefore(todayStart)) {
      return todayStart.subtract(const Duration(days: 1));
    }
    return todayStart;
  }

  /// Whether [a] and [b] fall in the same day period for [dayStartSeconds].
  static bool isSamePeriod(DateTime a, DateTime b, int dayStartSeconds) =>
      periodStart(a, dayStartSeconds) == periodStart(b, dayStartSeconds);

  /// Count for the current period, resetting when [timesRingDay] is stale.
  static int countForDay({
    required int timesRingToday,
    required DateTime? timesRingDay,
    required DateTime now,
    int dayStartSeconds = 0,
  }) {
    if (timesRingDay == null) return 0;
    if (!isSamePeriod(timesRingDay, now, dayStartSeconds)) return 0;
    return timesRingToday;
  }

  /// `true` when another fresh ring is allowed in the current period.
  ///
  /// [maxTimesPerDay] of `0` means unlimited.
  static bool canRingToday({
    required int maxTimesPerDay,
    required int timesRingToday,
    required DateTime? timesRingDay,
    required DateTime now,
    int dayStartSeconds = 0,
  }) {
    if (maxTimesPerDay <= 0) return true;
    final count = countForDay(
      timesRingToday: timesRingToday,
      timesRingDay: timesRingDay,
      now: now,
      dayStartSeconds: dayStartSeconds,
    );
    return count < maxTimesPerDay;
  }

  /// Prefer the next period start ("Start at time of day") over [proposed]
  /// when the daily cap is enabled and either:
  /// * the cap is exhausted, or
  /// * [proposed] falls on or after that next day-start boundary.
  ///
  /// [maxTimesPerDay] of `0` means the feature is off; [proposed] is unchanged.
  static DateTime deferIfDailyLimitReached({
    required DateTime proposed,
    required int maxTimesPerDay,
    required int timesRingToday,
    required DateTime? timesRingDay,
    required DateTime now,
    int dayStartSeconds = 0,
  }) {
    if (maxTimesPerDay <= 0) return proposed;
    final dayStart = nextPeriodStartAfter(now, dayStartSeconds);
    // Interval math must not skip past the next day-start into a new period.
    if (!proposed.isBefore(dayStart)) {
      return dayStart;
    }
    final count = countForDay(
      timesRingToday: timesRingToday,
      timesRingDay: timesRingDay,
      now: now,
      dayStartSeconds: dayStartSeconds,
    );
    if (count < maxTimesPerDay) return proposed;
    return dayStart;
  }

  /// Next day-period boundary after [now] (the next "Start at time of day").
  static DateTime nextPeriodStartAfter(DateTime now, int dayStartSeconds) =>
      periodStart(now, dayStartSeconds).add(const Duration(days: 1));

  /// First trigger when creating or importing a routine.
  ///
  /// When the daily cap is enabled, schedule the next "Start at time of day"
  /// so the first ring opens the daily cycle. Otherwise use [now] plus
  /// [interval]. Then defer to the next enabled weekday when needed.
  static DateTime initialTriggerTime({
    required DateTime now,
    required Duration interval,
    required bool maxTimesPerDayEnabled,
    int dayStartSeconds = 0,
    int enabledWeekdays = 0x7F,
  }) {
    final proposed = maxTimesPerDayEnabled
        ? nextPeriodStartAfter(now, dayStartSeconds)
        : now.add(interval);
    return RA_WeekdaySchedule.deferToEnabledDay(proposed, enabledWeekdays);
  }

  /// Whether [nextTrigger] is the next "Start at time of day" after [now].
  ///
  /// True when the daily cap deferred the next ring to the period reset, so
  /// skipping ahead would land on the same boundary again.
  static bool isScheduledAtNextPeriodStart({
    required DateTime nextTrigger,
    required int dayStartSeconds,
    DateTime? now,
  }) {
    final expected = nextPeriodStartAfter(
      now ?? DateTime.now(),
      dayStartSeconds,
    );
    return nextTrigger.millisecondsSinceEpoch ==
        expected.millisecondsSinceEpoch;
  }

  /// Next fire after a paused day-start target was missed: the sooner of
  /// [now] plus [intervalSeconds] and the next period start.
  static DateTime earliestResumeAfterMissedDayStart({
    required DateTime now,
    required int intervalSeconds,
    required int dayStartSeconds,
  }) {
    final afterInterval = now.add(Duration(seconds: intervalSeconds));
    final dayStart = nextPeriodStartAfter(now, dayStartSeconds);
    return afterInterval.isBefore(dayStart) ? afterInterval : dayStart;
  }
}
