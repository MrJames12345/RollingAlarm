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
  static DateTime calculateNextTrigger({
    required RA_AlarmActionTypeCodeEnum Action,
    required DriftCompensationTypeCodeEnum Compensation,
    required int IntervalSeconds,
    required int SnoozeSeconds,
    required DateTime InitialRingTime,
    required DateTime Now,
  }) {
    final interval = Duration(seconds: IntervalSeconds);
    final snoozeDuration = Duration(seconds: SnoozeSeconds);

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
        var next = InitialRingTime.add(Interval);
        while (!next.isAfter(Now)) {
          next = next.add(Interval);
        }
        return next;
    }
  }
}
