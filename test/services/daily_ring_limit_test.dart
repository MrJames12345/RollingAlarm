import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_alarm/services/daily_ring_limit.dart';

void main() {
  group('RA_DailyRingLimit', () {
    final now = DateTime(2026, 7, 26, 15, 30);
    const sixAm = 6 * 3600;

    test('periodStart uses midnight when dayStartSeconds is 0', () {
      expect(RA_DailyRingLimit.periodStart(now, 0), DateTime(2026, 7, 26));
    });

    test('periodStart rolls back before the custom start time', () {
      final early = DateTime(2026, 7, 26, 5, 0);
      expect(
        RA_DailyRingLimit.periodStart(early, sixAm),
        DateTime(2026, 7, 25, 6),
      );
      expect(
        RA_DailyRingLimit.periodStart(now, sixAm),
        DateTime(2026, 7, 26, 6),
      );
    });

    test('countForDay resets when TimesRingDay is a prior period', () {
      expect(
        RA_DailyRingLimit.countForDay(
          timesRingToday: 4,
          timesRingDay: DateTime(2026, 7, 25),
          now: now,
        ),
        0,
      );
    });

    test('countForDay keeps count in the same custom period', () {
      expect(
        RA_DailyRingLimit.countForDay(
          timesRingToday: 2,
          timesRingDay: DateTime(2026, 7, 26, 6),
          now: now,
          dayStartSeconds: sixAm,
        ),
        2,
      );
      expect(
        RA_DailyRingLimit.countForDay(
          timesRingToday: 2,
          timesRingDay: DateTime(2026, 7, 25, 6),
          now: DateTime(2026, 7, 26, 5),
          dayStartSeconds: sixAm,
        ),
        2,
      );
    });

    test('canRingToday treats 0 max as unlimited', () {
      expect(
        RA_DailyRingLimit.canRingToday(
          maxTimesPerDay: 0,
          timesRingToday: 99,
          timesRingDay: now,
          now: now,
        ),
        isTrue,
      );
    });

    test('canRingToday blocks when count reaches the max', () {
      expect(
        RA_DailyRingLimit.canRingToday(
          maxTimesPerDay: 3,
          timesRingToday: 3,
          timesRingDay: now,
          now: now,
        ),
        isFalse,
      );
      expect(
        RA_DailyRingLimit.canRingToday(
          maxTimesPerDay: 3,
          timesRingToday: 2,
          timesRingDay: now,
          now: now,
        ),
        isTrue,
      );
    });

    test('deferIfDailyLimitReached schedules the next day-start', () {
      final proposed = DateTime(2026, 7, 26, 19, 45, 10);
      final deferred = RA_DailyRingLimit.deferIfDailyLimitReached(
        proposed: proposed,
        maxTimesPerDay: 2,
        timesRingToday: 2,
        timesRingDay: now,
        now: now,
        dayStartSeconds: sixAm,
      );
      expect(deferred, DateTime(2026, 7, 27, 6));
    });

    test(
      'deferIfDailyLimitReached snaps next-period proposals to day-start',
      () {
        final proposed = DateTime(2026, 7, 27, 8);
        final deferred = RA_DailyRingLimit.deferIfDailyLimitReached(
          proposed: proposed,
          maxTimesPerDay: 1,
          timesRingToday: 1,
          timesRingDay: DateTime(2026, 7, 26, 6),
          now: now,
          dayStartSeconds: sixAm,
        );
        expect(deferred, DateTime(2026, 7, 27, 6));
      },
    );

    test(
      'deferIfDailyLimitReached snaps past day-start even under the cap',
      () {
        // Under the cap, but interval lands after tomorrow's 6am day-start.
        final proposed = DateTime(2026, 7, 27, 8);
        final deferred = RA_DailyRingLimit.deferIfDailyLimitReached(
          proposed: proposed,
          maxTimesPerDay: 3,
          timesRingToday: 1,
          timesRingDay: DateTime(2026, 7, 26, 6),
          now: now,
          dayStartSeconds: sixAm,
        );
        expect(deferred, DateTime(2026, 7, 27, 6));
      },
    );

    test(
      'deferIfDailyLimitReached snaps to today day-start when still before it',
      () {
        final early = DateTime(2026, 7, 26, 5, 0);
        final proposed = DateTime(2026, 7, 26, 7, 30);
        final deferred = RA_DailyRingLimit.deferIfDailyLimitReached(
          proposed: proposed,
          maxTimesPerDay: 3,
          timesRingToday: 0,
          timesRingDay: null,
          now: early,
          dayStartSeconds: sixAm,
        );
        expect(deferred, DateTime(2026, 7, 26, 6));
      },
    );

    test('deferIfDailyLimitReached leaves proposed alone under the cap', () {
      final proposed = DateTime(2026, 7, 26, 19, 45);
      final deferred = RA_DailyRingLimit.deferIfDailyLimitReached(
        proposed: proposed,
        maxTimesPerDay: 3,
        timesRingToday: 2,
        timesRingDay: now,
        now: now,
        dayStartSeconds: sixAm,
      );
      expect(deferred, proposed);
    });

    test('nextPeriodStartAfter returns the next day-start boundary', () {
      expect(
        RA_DailyRingLimit.nextPeriodStartAfter(now, 0),
        DateTime(2026, 7, 27),
      );
      expect(
        RA_DailyRingLimit.nextPeriodStartAfter(now, sixAm),
        DateTime(2026, 7, 27, 6),
      );
      expect(
        RA_DailyRingLimit.nextPeriodStartAfter(DateTime(2026, 7, 26, 5), sixAm),
        DateTime(2026, 7, 26, 6),
      );
    });

    test('initialTriggerTime uses day start when the daily cap is on', () {
      const interval = Duration(hours: 2, minutes: 30);
      expect(
        RA_DailyRingLimit.initialTriggerTime(
          now: now,
          interval: interval,
          maxTimesPerDayEnabled: true,
          dayStartSeconds: sixAm,
        ),
        DateTime(2026, 7, 27, 6),
      );
      expect(
        RA_DailyRingLimit.initialTriggerTime(
          now: DateTime(2026, 7, 26, 5),
          interval: interval,
          maxTimesPerDayEnabled: true,
          dayStartSeconds: sixAm,
        ),
        DateTime(2026, 7, 26, 6),
      );
    });

    test('initialTriggerTime uses now plus interval when the cap is off', () {
      const interval = Duration(hours: 2, minutes: 30);
      expect(
        RA_DailyRingLimit.initialTriggerTime(
          now: now,
          interval: interval,
          maxTimesPerDayEnabled: false,
          dayStartSeconds: sixAm,
        ),
        now.add(interval),
      );
    });

    test('initialTriggerTime defers onto an enabled weekday', () {
      // now is Sunday 15:30; now + 2h30m is Sunday 18:00 -> Monday 18:00.
      const interval = Duration(hours: 2, minutes: 30);
      const weekdays = 0x1F; // Mon to Fri
      expect(now.weekday, DateTime.sunday);
      expect(
        RA_DailyRingLimit.initialTriggerTime(
          now: now,
          interval: interval,
          maxTimesPerDayEnabled: false,
          enabledWeekdays: weekdays,
        ),
        DateTime(2026, 7, 27, 18),
      );
    });

    test('isScheduledAtNextPeriodStart matches the next day-start only', () {
      expect(
        RA_DailyRingLimit.isScheduledAtNextPeriodStart(
          nextTrigger: DateTime(2026, 7, 27, 6),
          dayStartSeconds: sixAm,
          now: now,
        ),
        isTrue,
      );
      expect(
        RA_DailyRingLimit.isScheduledAtNextPeriodStart(
          nextTrigger: DateTime(2026, 7, 26, 19, 45),
          dayStartSeconds: sixAm,
          now: now,
        ),
        isFalse,
      );
      expect(
        RA_DailyRingLimit.isScheduledAtNextPeriodStart(
          nextTrigger: DateTime(2026, 7, 26, 6),
          dayStartSeconds: sixAm,
          now: DateTime(2026, 7, 26, 5),
        ),
        isTrue,
      );
    });

    test(
      'earliestResumeAfterMissedDayStart picks the sooner of interval and day-start',
      () {
        // Interval (2h) sooner than next day-start (~11h from 15:30).
        expect(
          RA_DailyRingLimit.earliestResumeAfterMissedDayStart(
            now: now,
            intervalSeconds: 2 * 3600,
            dayStartSeconds: sixAm,
          ),
          now.add(const Duration(hours: 2)),
        );
        // Long interval loses to next day-start.
        expect(
          RA_DailyRingLimit.earliestResumeAfterMissedDayStart(
            now: now,
            intervalSeconds: 20 * 3600,
            dayStartSeconds: sixAm,
          ),
          DateTime(2026, 7, 27, 6),
        );
      },
    );
  });
}
