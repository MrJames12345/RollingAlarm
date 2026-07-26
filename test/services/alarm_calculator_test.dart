import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_alarm/services/alarm_calculator.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';
import 'package:rolling_alarm/enums/alarm_action_type_code.dart';

void main() {
  group('RA_AlarmCalculator', () {
    // --------------------------------------------------------------------- //
    // Baseline interval: dismiss at 06:00, interval 4h30m, next 10:30:00
    // --------------------------------------------------------------------- //
    test('baseline interval calculates correctly on dismiss', () {
      final now = DateTime(2026, 1, 1, 6, 0, 0);
      final result = RA_AlarmCalculator.calculateNextTrigger(
        Action: RA_AlarmActionTypeCodeEnum.Dismiss,
        Compensation: DriftCompensationTypeCodeEnum.ActualDismissal,
        IntervalSeconds: 16200,
        SnoozeSeconds: 540,
        InitialRingTime: now,
        Now: now,
      );
      expect(result, DateTime(2026, 1, 1, 10, 30, 0));
    });

    test('interval seconds are included in dismiss math', () {
      final now = DateTime(2026, 1, 1, 6, 0, 0);
      final result = RA_AlarmCalculator.calculateNextTrigger(
        Action: RA_AlarmActionTypeCodeEnum.Dismiss,
        Compensation: DriftCompensationTypeCodeEnum.ActualDismissal,
        IntervalSeconds: 90,
        SnoozeSeconds: 300,
        InitialRingTime: now,
        Now: now,
      );
      expect(result, DateTime(2026, 1, 1, 6, 1, 30));
    });

    // --------------------------------------------------------------------- //
    // ActualDismissal: rang 06:00, snoozed twice (9m each), dismissed 06:23:17
    // Next = 06:23:17 + 4h30m = 10:53:17 (drift accumulates)
    // --------------------------------------------------------------------- //
    test('ActualDismissal bases next trigger on dismiss time (drift accumulates)', () {
      final initialRing = DateTime(2026, 1, 1, 6, 0, 0);
      final dismissTime = DateTime(2026, 1, 1, 6, 23, 17);
      final result = RA_AlarmCalculator.calculateNextTrigger(
        Action: RA_AlarmActionTypeCodeEnum.Dismiss,
        Compensation: DriftCompensationTypeCodeEnum.ActualDismissal,
        IntervalSeconds: 16200,
        SnoozeSeconds: 540,
        InitialRingTime: initialRing,
        Now: dismissTime,
      );
      expect(result, DateTime(2026, 1, 1, 10, 53, 17));
    });

    // --------------------------------------------------------------------- //
    // InitialRing: identical inputs give next = 06:00:00 + 4h30m = 10:30:00
    // Schedule self-corrects; snooze time is absorbed.
    // --------------------------------------------------------------------- //
    test('InitialRing bases next trigger on initial ring time (self-corrects)', () {
      final initialRing = DateTime(2026, 1, 1, 6, 0, 0);
      final dismissTime = DateTime(2026, 1, 1, 6, 23, 17);
      final result = RA_AlarmCalculator.calculateNextTrigger(
        Action: RA_AlarmActionTypeCodeEnum.Dismiss,
        Compensation: DriftCompensationTypeCodeEnum.InitialRing,
        IntervalSeconds: 16200,
        SnoozeSeconds: 540,
        InitialRingTime: initialRing,
        Now: dismissTime,
      );
      expect(result, DateTime(2026, 1, 1, 10, 30, 0));
    });

    // --------------------------------------------------------------------- //
    // Bounded drift: 10 consecutive InitialRing dismiss cycles with varying
    // snooze durations, so the 10th trigger = first ring + 10 * interval exactly.
    // --------------------------------------------------------------------- //
    test('InitialRing produces zero cumulative drift across 10 cycles', () {
      const intervalHours = 2;
      const intervalMinutes = 0;
      const intervalDuration = Duration(hours: intervalHours, minutes: intervalMinutes);

      var currentInitialRing = DateTime(2026, 1, 1, 8, 0, 0);
      final firstRing = currentInitialRing;

      // Simulate 10 cycles with random-ish snooze delays
      final snoozeDurations = [3, 7, 12, 1, 9, 15, 5, 8, 11, 6];

      for (int i = 0; i < 10; i++) {
        // Simulate a dismiss that happens snoozeDurations[i] minutes after ring
        final dismissTime = currentInitialRing.add(Duration(minutes: snoozeDurations[i]));

        final nextTrigger = RA_AlarmCalculator.calculateNextTrigger(
          Action: RA_AlarmActionTypeCodeEnum.Dismiss,
          Compensation: DriftCompensationTypeCodeEnum.InitialRing,
          IntervalSeconds: (intervalHours * 3600) + (intervalMinutes * 60),
          SnoozeSeconds: 540,
          InitialRingTime: currentInitialRing,
          Now: dismissTime,
        );

        // The next initial ring is the next trigger time
        currentInitialRing = nextTrigger;
      }

      // After 10 cycles, should be exactly 10 intervals from the first ring
      expect(currentInitialRing, firstRing.add(intervalDuration * 10));
    });

    // --------------------------------------------------------------------- //
    // Snooze: basic snooze returns Now + SnoozeMinutes
    // --------------------------------------------------------------------- //
    test('snooze returns now plus snooze minutes', () {
      final now = DateTime(2026, 1, 1, 6, 0, 0);
      final result = RA_AlarmCalculator.calculateNextTrigger(
        Action: RA_AlarmActionTypeCodeEnum.Snooze,
        Compensation: DriftCompensationTypeCodeEnum.ActualDismissal,
        IntervalSeconds: 16200,
        SnoozeSeconds: 540,
        InitialRingTime: now,
        Now: now,
      );
      expect(result, DateTime(2026, 1, 1, 6, 9, 0));
    });

    // --------------------------------------------------------------------- //
    // Snooze has no cap: always returns Now + SnoozeMinutes
    // --------------------------------------------------------------------- //
    test('repeated snooze always returns now plus snooze minutes (ActualDismissal)', () {
      final initialRing = DateTime(2026, 1, 1, 6, 0, 0);
      final now = DateTime(2026, 1, 1, 6, 27, 0);
      final result = RA_AlarmCalculator.calculateNextTrigger(
        Action: RA_AlarmActionTypeCodeEnum.Snooze,
        Compensation: DriftCompensationTypeCodeEnum.ActualDismissal,
        IntervalSeconds: 16200,
        SnoozeSeconds: 540,
        InitialRingTime: initialRing,
        Now: now,
      );
      expect(result, DateTime(2026, 1, 1, 6, 36, 0));
    });

    test('repeated snooze always returns now plus snooze minutes (InitialRing)', () {
      final initialRing = DateTime(2026, 1, 1, 6, 0, 0);
      final now = DateTime(2026, 1, 1, 6, 27, 0);
      final result = RA_AlarmCalculator.calculateNextTrigger(
        Action: RA_AlarmActionTypeCodeEnum.Snooze,
        Compensation: DriftCompensationTypeCodeEnum.InitialRing,
        IntervalSeconds: 16200,
        SnoozeSeconds: 540,
        InitialRingTime: initialRing,
        Now: now,
      );
      expect(result, DateTime(2026, 1, 1, 6, 36, 0));
    });

    // --------------------------------------------------------------------- //
    // Skip: cancels pending trigger, returns Now + interval regardless of mode
    // --------------------------------------------------------------------- //
    test('skip returns now plus interval regardless of compensation mode (ActualDismissal)', () {
      final initialRing = DateTime(2026, 1, 1, 6, 0, 0);
      final now = DateTime(2026, 1, 1, 7, 15, 0);
      final result = RA_AlarmCalculator.calculateNextTrigger(
        Action: RA_AlarmActionTypeCodeEnum.Skip,
        Compensation: DriftCompensationTypeCodeEnum.ActualDismissal,
        IntervalSeconds: 16200,
        SnoozeSeconds: 540,
        InitialRingTime: initialRing,
        Now: now,
      );
      expect(result, DateTime(2026, 1, 1, 11, 45, 0));
    });

    test('skip returns now plus interval regardless of compensation mode (InitialRing)', () {
      final initialRing = DateTime(2026, 1, 1, 6, 0, 0);
      final now = DateTime(2026, 1, 1, 7, 15, 0);
      final result = RA_AlarmCalculator.calculateNextTrigger(
        Action: RA_AlarmActionTypeCodeEnum.Skip,
        Compensation: DriftCompensationTypeCodeEnum.InitialRing,
        IntervalSeconds: 16200,
        SnoozeSeconds: 540,
        InitialRingTime: initialRing,
        Now: now,
      );
      // Skip always uses Now, not InitialRingTime
      expect(result, DateTime(2026, 1, 1, 11, 45, 0));
    });

    // --------------------------------------------------------------------- //
    // AutoSnooze: same as snooze but triggered by inaction
    // --------------------------------------------------------------------- //
    test('autoSnooze returns now plus snooze minutes', () {
      final now = DateTime(2026, 1, 1, 6, 5, 0);
      final result = RA_AlarmCalculator.calculateNextTrigger(
        Action: RA_AlarmActionTypeCodeEnum.AutoSnooze,
        Compensation: DriftCompensationTypeCodeEnum.ActualDismissal,
        IntervalSeconds: 16200,
        SnoozeSeconds: 540,
        InitialRingTime: DateTime(2026, 1, 1, 6, 0, 0),
        Now: now,
      );
      expect(result, DateTime(2026, 1, 1, 6, 14, 0));
    });

    // --------------------------------------------------------------------- //
    // AutoSnooze has no cap: always returns Now + SnoozeMinutes
    // --------------------------------------------------------------------- //
    test('repeated autoSnooze always returns now plus snooze minutes', () {
      final initialRing = DateTime(2026, 1, 1, 6, 0, 0);
      final now = DateTime(2026, 1, 1, 6, 27, 0);
      final result = RA_AlarmCalculator.calculateNextTrigger(
        Action: RA_AlarmActionTypeCodeEnum.AutoSnooze,
        Compensation: DriftCompensationTypeCodeEnum.ActualDismissal,
        IntervalSeconds: 16200,
        SnoozeSeconds: 540,
        InitialRingTime: initialRing,
        Now: now,
      );
      expect(result, DateTime(2026, 1, 1, 6, 36, 0));
    });

    // --------------------------------------------------------------------- //
    // Boundary: interval crossing midnight
    // --------------------------------------------------------------------- //
    test('interval crossing midnight calculates correctly', () {
      final now = DateTime(2026, 1, 1, 22, 0, 0);
      final result = RA_AlarmCalculator.calculateNextTrigger(
        Action: RA_AlarmActionTypeCodeEnum.Dismiss,
        Compensation: DriftCompensationTypeCodeEnum.ActualDismissal,
        IntervalSeconds: 16200,
        SnoozeSeconds: 540,
        InitialRingTime: now,
        Now: now,
      );
      expect(result, DateTime(2026, 1, 2, 2, 30, 0));
    });

    // --------------------------------------------------------------------- //
    // Boundary: DST spring-forward transition (clock jumps 01:59 to 03:00)
    // Using US Eastern: 2026-03-08 at 2:00 AM
    // A dismiss at 01:00 with a 2h interval lands at 03:00 wall clock,
    // which is exactly 1 hour of elapsed real time due to the spring-forward.
    // DateTime arithmetic in Dart adds Duration to the underlying instant,
    // so the wall clock result is 03:00, which is correct for an alarm.
    // --------------------------------------------------------------------- //
    test('interval crossing DST spring-forward boundary', () {
      // Simulating: dismiss at 2026-03-08 00:30:00, interval 2h
      // Next trigger: 2026-03-08 02:30:00 (Dart DateTime is naive/UTC-unaware,
      // so this is straightforward addition)
      final now = DateTime(2026, 3, 8, 0, 30, 0);
      final result = RA_AlarmCalculator.calculateNextTrigger(
        Action: RA_AlarmActionTypeCodeEnum.Dismiss,
        Compensation: DriftCompensationTypeCodeEnum.ActualDismissal,
        IntervalSeconds: 7200,
        SnoozeSeconds: 540,
        InitialRingTime: now,
        Now: now,
      );
      expect(result, DateTime(2026, 3, 8, 2, 30, 0));
    });

    // --------------------------------------------------------------------- //
    // Boundary: DST fall-back transition (US Eastern 2026-11-01, 2:00 AM
    // repeats). Naive DateTime addition still yields an exact wall clock
    // result, which is what the scheduler persists.
    // --------------------------------------------------------------------- //
    test('interval crossing DST fall-back boundary', () {
      final now = DateTime(2026, 11, 1, 0, 30, 0);
      final result = RA_AlarmCalculator.calculateNextTrigger(
        Action: RA_AlarmActionTypeCodeEnum.Dismiss,
        Compensation: DriftCompensationTypeCodeEnum.ActualDismissal,
        IntervalSeconds: 7200,
        SnoozeSeconds: 540,
        InitialRingTime: now,
        Now: now,
      );
      expect(result, DateTime(2026, 11, 1, 2, 30, 0));
    });

    // --------------------------------------------------------------------- //
    // Cumulative snooze accumulation with ActualDismissal across multi-snooze
    // --------------------------------------------------------------------- //
    test('cumulative drift across multi-snooze cycle with ActualDismissal', () {
      // Ring at 06:00, snooze 3 times (9m each), dismiss at ~06:27
      // Each snooze: 06:00, 06:09, 06:18, 06:27
      // Dismiss at 06:27 with ActualDismissal: next = 06:27 + 4h30m = 10:57:00
      final initialRing = DateTime(2026, 1, 1, 6, 0, 0);

      // First snooze at ring time
      var snoozeResult = RA_AlarmCalculator.calculateNextTrigger(
        Action: RA_AlarmActionTypeCodeEnum.Snooze,
        Compensation: DriftCompensationTypeCodeEnum.ActualDismissal,
        IntervalSeconds: 16200,
        SnoozeSeconds: 540,
        InitialRingTime: initialRing,
        Now: initialRing,
      );
      expect(snoozeResult, DateTime(2026, 1, 1, 6, 9, 0));

      // Second snooze
      snoozeResult = RA_AlarmCalculator.calculateNextTrigger(
        Action: RA_AlarmActionTypeCodeEnum.Snooze,
        Compensation: DriftCompensationTypeCodeEnum.ActualDismissal,
        IntervalSeconds: 16200,
        SnoozeSeconds: 540,
        InitialRingTime: initialRing,
        Now: snoozeResult,
      );
      expect(snoozeResult, DateTime(2026, 1, 1, 6, 18, 0));

      // Third snooze
      snoozeResult = RA_AlarmCalculator.calculateNextTrigger(
        Action: RA_AlarmActionTypeCodeEnum.Snooze,
        Compensation: DriftCompensationTypeCodeEnum.ActualDismissal,
        IntervalSeconds: 16200,
        SnoozeSeconds: 540,
        InitialRingTime: initialRing,
        Now: snoozeResult,
      );
      expect(snoozeResult, DateTime(2026, 1, 1, 6, 27, 0));

      // Dismiss after the third snooze
      final dismissResult = RA_AlarmCalculator.calculateNextTrigger(
        Action: RA_AlarmActionTypeCodeEnum.Dismiss,
        Compensation: DriftCompensationTypeCodeEnum.ActualDismissal,
        IntervalSeconds: 16200,
        SnoozeSeconds: 540,
        InitialRingTime: initialRing,
        Now: snoozeResult,
      );
      // Drift accumulated: 06:27 + 4:30 = 10:57
      expect(dismissResult, DateTime(2026, 1, 1, 10, 57, 0));
    });
  });
}
