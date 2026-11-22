import 'package:rolling_alarm/enums/alarm_action_type_code.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';

/// Pure arithmetic calculator for alarm scheduling.
///
/// Takes only primitives and hand-written enums, with no Drift-generated types,
/// no plugins, and no ambient clock. This makes it fully testable before
/// build_runner or any platform code exists.
class RA_AlarmCalculator {
  RA_AlarmCalculator._();

  /// Calculates the next trigger [DateTime] for an alarm based on the
  /// action taken, compensation mode, and current state.
  ///
  /// - [Action]: what the user (or system) did, one of Dismiss, Snooze, Skip, or AutoSnooze.
  /// - [Compensation]: whether the next interval is based on the actual
  ///   dismiss time ([ActualDismissal]) or the original ring time ([InitialRing]).
  /// - [IntervalSeconds]: total repeating interval length in seconds.
  /// - [SnoozeSeconds]: duration of a single snooze in seconds (also used when the alarm
  ///   is ignored; auto-snooze is always on).
  /// - [InitialRingTime]: the timestamp when the alarm first rang this cycle
  ///   (before any snoozes).
  /// - [Now]: the injected current time (never uses DateTime.now()).
  /// Fallback seconds used if a malformed caller passes a non-positive duration.
  static const int _fallbackSeconds = 60;

  static DateTime calculateNextTrigger({
    required RA_AlarmActionTypeCodeEnum Action,
    required DriftCompensationTypeCodeEnum Compensation,
    required int IntervalSeconds,
    required int SnoozeSeconds,
    required DateTime InitialRingTime,
    required DateTime Now,
  }) {
    final safeIntervalSeconds = IntervalSeconds < 1
        ? _fallbackSeconds
        : IntervalSeconds;
    final safeSnoozeSeconds = SnoozeSeconds < 1
        ? _fallbackSeconds
        : SnoozeSeconds;
    final interval = Duration(seconds: safeIntervalSeconds);
    final snoozeDuration = Duration(seconds: safeSnoozeSeconds);

    return switch (Action) {
      RA_AlarmActionTypeCodeEnum.Dismiss => _calculateDismiss(
        Compensation: Compensation,
        Interval: interval,
        InitialRingTime: InitialRingTime,
        Now: Now,
      ),
      RA_AlarmActionTypeCodeEnum.Snooze ||
      RA_AlarmActionTypeCodeEnum.AutoSnooze => Now.add(snoozeDuration),
      RA_AlarmActionTypeCodeEnum.Skip => Now.add(interval),
    };
  }

  /// Internal dismiss calculation respecting the compensation mode.
  ///
  /// For [InitialRing], advances by whole intervals from [InitialRingTime]
  /// until the candidate is strictly after [Now]. A single
  /// `InitialRingTime + Interval` can already be in the past after a long
  /// snooze chain; without this skip, [scheduleNext] would clamp to now and
  /// re-ring immediately in a loop.
  static DateTime _calculateDismiss({
    required DriftCompensationTypeCodeEnum Compensation,
    required Duration Interval,
    required DateTime InitialRingTime,
    required DateTime Now,
  }) {
    switch (Compensation) {
      case DriftCompensationTypeCodeEnum.ActualDismissal:
        return Now.add(Interval);
      case DriftCompensationTypeCodeEnum.InitialRing:
        final safeInterval = Interval.inMicroseconds < 1
            ? const Duration(seconds: _fallbackSeconds)
            : Interval;
        var next = InitialRingTime.add(safeInterval);
        if (!next.isAfter(Now)) {
          final diffMicros = Now.difference(InitialRingTime).inMicroseconds;
          final intervalMicros = safeInterval.inMicroseconds;
          final steps = (diffMicros ~/ intervalMicros) + 1;
          next = InitialRingTime.add(
            Duration(microseconds: steps * intervalMicros),
          );
          while (!next.isAfter(Now)) {
            next = next.add(safeInterval);
          }
        }
        return next;
    }
  }
}
