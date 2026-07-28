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

  /// Prefer a day-start parking point over [proposed] when the daily cap is
  /// enabled and either:
  /// * the cap is exhausted (always the next *calendar* day's day-start, never
  ///   an upcoming day-start later today), or
  /// * [proposed] falls on or after the next period boundary (even under the
  ///   cap; long intervals must not skip into a new period).
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
    final count = countForDay(
      timesRingToday: timesRingToday,
      timesRingDay: timesRingDay,
      now: now,
      dayStartSeconds: dayStartSeconds,
    );
    if (count >= maxTimesPerDay) {
      return nextCalendarDayStart(now, dayStartSeconds);
    }
    final nextPeriodStart = nextPeriodStartAfter(now, dayStartSeconds);
    // Interval math must not skip past the next day-start into a new period.
    if (!proposed.isBefore(nextPeriodStart)) {
      return nextPeriodStart;
    }
    return proposed;
  }

  /// Next day-period boundary after [now] (the next "Start at time of day").
  ///
  /// When [now] is still before today's day-start clock, this is later *today*.
  static DateTime nextPeriodStartAfter(DateTime now, int dayStartSeconds) =>
      periodStart(now, dayStartSeconds).add(const Duration(days: 1));

  /// Day-start on the next calendar day after [now].
  ///
  /// Used when the daily cap is exhausted so the next fire is never scheduled
  /// for an upcoming day-start later on the same calendar day.
  static DateTime nextCalendarDayStart(DateTime now, int dayStartSeconds) {
    final offset = Duration(seconds: normalizeDayStartSeconds(dayStartSeconds));
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 1)).add(offset);
  }

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
    return RA_WeekdaySchedule.deferToEnabledDay(
      proposed,
      enabledWeekdays,
      dayStartSeconds: dayStartSeconds,
    );
  }

  /// Whether [trigger] lands exactly on a "Start at time of day" boundary.
  ///
  /// True for the immediate next day-start and for the day-start clock after
  /// weekday deferral. Used so pause/resume keep absolute day-start targets.
  ///
  /// Compares local time-of-day (hour/minute/second) so Drift round-trips and
  /// UTC/local representations of the same wall clock still match.
  static bool isPeriodStartTrigger({
    required DateTime trigger,
    required int dayStartSeconds,
  }) {
    final local = trigger.toLocal();
    final offset = normalizeDayStartSeconds(dayStartSeconds);
    final secondsOfDay = local.hour * 3600 + local.minute * 60 + local.second;
    return secondsOfDay == offset;
  }

  /// `true` when the daily cap is on and [count] has reached it.
  static bool isAtOrOverCap({
    required int count,
    required bool maxTimesPerDayEnabled,
    required int maxTimesPerDay,
  }) {
    if (!maxTimesPerDayEnabled || maxTimesPerDay <= 0) return false;
    return count >= maxTimesPerDay;
  }

  /// Remaps [previousNext] after an edit to day-start and/or max-times.
  ///
  /// When the effective daily cap changes relative to today's count:
  /// * newly at/over cap → next calendar day's "Start at time of day"
  /// * newly under cap → [now] plus [intervalSeconds] (still snapped by
  ///   [deferIfDailyLimitReached] so it cannot skip past day-start)
  ///
  /// Otherwise, if the upcoming fire was a day-start boundary and that clock
  /// changed, retarget to the new day-start. Always applies weekday deferral.
  static DateTime? retargetNextAfterEdit({
    required DateTime? previousNext,
    required int oldDayStartSeconds,
    required int newDayStartSeconds,
    required bool oldMaxTimesPerDayEnabled,
    required bool newMaxTimesPerDayEnabled,
    required int oldMaxTimesPerDay,
    required int newMaxTimesPerDay,
    required int timesRingToday,
    required DateTime? timesRingDay,
    required DateTime now,
    required int intervalSeconds,
    required int enabledWeekdays,
  }) {
    if (previousNext == null) return null;

    final oldStart = normalizeDayStartSeconds(oldDayStartSeconds);
    final newStart = normalizeDayStartSeconds(newDayStartSeconds);
    final count = countForDay(
      timesRingToday: timesRingToday,
      timesRingDay: timesRingDay,
      now: now,
      dayStartSeconds: oldStart,
    );

    final capChanged =
        oldMaxTimesPerDayEnabled != newMaxTimesPerDayEnabled ||
        (oldMaxTimesPerDayEnabled &&
            newMaxTimesPerDayEnabled &&
            oldMaxTimesPerDay != newMaxTimesPerDay);

    final wasAtCap = isAtOrOverCap(
      count: count,
      maxTimesPerDayEnabled: oldMaxTimesPerDayEnabled,
      maxTimesPerDay: oldMaxTimesPerDay,
    );
    final isAtCap = isAtOrOverCap(
      count: count,
      maxTimesPerDayEnabled: newMaxTimesPerDayEnabled,
      maxTimesPerDay: newMaxTimesPerDay,
    );

    late final DateTime candidate;
    if (capChanged && isAtCap && !wasAtCap) {
      candidate = nextCalendarDayStart(now, newStart);
    } else if (capChanged && !isAtCap && wasAtCap) {
      candidate = deferIfDailyLimitReached(
        proposed: now.add(Duration(seconds: intervalSeconds)),
        maxTimesPerDay: newMaxTimesPerDayEnabled ? newMaxTimesPerDay : 0,
        timesRingToday: timesRingToday,
        timesRingDay: timesRingDay,
        now: now,
        dayStartSeconds: newStart,
      );
    } else if (oldStart != newStart &&
        isPeriodStartTrigger(
          trigger: previousNext,
          dayStartSeconds: oldStart,
        )) {
      candidate = nextPeriodStartAfter(now, newStart);
    } else {
      candidate = previousNext;
    }

    return RA_WeekdaySchedule.deferToEnabledDay(
      candidate,
      enabledWeekdays,
      dayStartSeconds: newStart,
    );
  }

  /// Remaps [previousNext] when saving an edit that changes day-start.
  ///
  /// If the upcoming fire is a day-start boundary under [oldDayStartSeconds],
  /// move it to the next occurrence of [newDayStartSeconds]. Always applies
  /// weekday deferral with [enabledWeekdays]. Returns null when there is no
  /// upcoming fire.
  static DateTime? retargetNextAfterDayStartEdit({
    required DateTime? previousNext,
    required int oldDayStartSeconds,
    required int newDayStartSeconds,
    required DateTime now,
    required int enabledWeekdays,
  }) => retargetNextAfterEdit(
    previousNext: previousNext,
    oldDayStartSeconds: oldDayStartSeconds,
    newDayStartSeconds: newDayStartSeconds,
    oldMaxTimesPerDayEnabled: false,
    newMaxTimesPerDayEnabled: false,
    oldMaxTimesPerDay: 0,
    newMaxTimesPerDay: 0,
    timesRingToday: 0,
    timesRingDay: null,
    now: now,
    intervalSeconds: 0,
    enabledWeekdays: enabledWeekdays,
  );

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

  /// Remaps [previousNext] after the user zeros today's ring counter.
  ///
  /// When the prior count was at/over the daily cap and [previousNext] is
  /// parked on a day-start boundary, resume with [now] plus [intervalSeconds]
  /// (still snapped by [deferIfDailyLimitReached] and weekday deferral).
  /// Otherwise returns [previousNext] unchanged.
  ///
  /// Callers should persist the zeroed count before or alongside applying the
  /// returned time; this helper always evaluates the post-reset count as `0`.
  static DateTime? retargetNextAfterCounterReset({
    required DateTime? previousNext,
    required int priorTimesRingToday,
    required DateTime? timesRingDay,
    required bool maxTimesPerDayEnabled,
    required int maxTimesPerDay,
    required DateTime now,
    required int intervalSeconds,
    required int dayStartSeconds,
    required int enabledWeekdays,
  }) {
    if (previousNext == null) return null;

    final dayStart = normalizeDayStartSeconds(dayStartSeconds);
    final priorCount = countForDay(
      timesRingToday: priorTimesRingToday,
      timesRingDay: timesRingDay,
      now: now,
      dayStartSeconds: dayStart,
    );
    final wasAtCap = isAtOrOverCap(
      count: priorCount,
      maxTimesPerDayEnabled: maxTimesPerDayEnabled,
      maxTimesPerDay: maxTimesPerDay,
    );
    if (!wasAtCap ||
        !isPeriodStartTrigger(
          trigger: previousNext,
          dayStartSeconds: dayStart,
        )) {
      return previousNext;
    }

    final period = periodStart(now, dayStart);
    final candidate = deferIfDailyLimitReached(
      proposed: now.add(Duration(seconds: intervalSeconds)),
      maxTimesPerDay: maxTimesPerDayEnabled ? maxTimesPerDay : 0,
      timesRingToday: 0,
      timesRingDay: period,
      now: now,
      dayStartSeconds: dayStart,
    );
    return RA_WeekdaySchedule.deferToEnabledDay(
      candidate,
      enabledWeekdays,
      dayStartSeconds: dayStart,
    );
  }
}
