import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_alarm/services/weekday_schedule.dart';

void main() {
  group('RA_WeekdaySchedule', () {
    test('allDaysMask enables every Dart weekday', () {
      for (var weekday = 1; weekday <= 7; weekday++) {
        expect(
          RA_WeekdaySchedule.isEnabled(RA_WeekdaySchedule.allDaysMask, weekday),
          isTrue,
        );
      }
    });

    test('isEnabled reads Monday-first bits', () {
      // Monday only.
      const mondayOnly = 1 << 0;
      expect(RA_WeekdaySchedule.isEnabled(mondayOnly, DateTime.monday), isTrue);
      expect(
        RA_WeekdaySchedule.isEnabled(mondayOnly, DateTime.tuesday),
        isFalse,
      );
      expect(
        RA_WeekdaySchedule.isEnabled(mondayOnly, DateTime.sunday),
        isFalse,
      );

      // Sunday only (bit 6).
      const sundayOnly = 1 << 6;
      expect(RA_WeekdaySchedule.isEnabled(sundayOnly, DateTime.sunday), isTrue);
      expect(
        RA_WeekdaySchedule.isEnabled(sundayOnly, DateTime.saturday),
        isFalse,
      );
    });

    test('toggleWeekday turns days on and off', () {
      var mask = RA_WeekdaySchedule.allDaysMask;
      mask = RA_WeekdaySchedule.toggleWeekday(mask, DateTime.saturday);
      mask = RA_WeekdaySchedule.toggleWeekday(mask, DateTime.sunday);
      expect(RA_WeekdaySchedule.isEnabled(mask, DateTime.friday), isTrue);
      expect(RA_WeekdaySchedule.isEnabled(mask, DateTime.saturday), isFalse);
      expect(RA_WeekdaySchedule.isEnabled(mask, DateTime.sunday), isFalse);

      mask = RA_WeekdaySchedule.toggleWeekday(mask, DateTime.saturday);
      expect(RA_WeekdaySchedule.isEnabled(mask, DateTime.saturday), isTrue);
    });

    test('toggleWeekday refuses to clear the last day', () {
      const mondayOnly = 1 << 0;
      expect(
        RA_WeekdaySchedule.toggleWeekday(mondayOnly, DateTime.monday),
        mondayOnly,
      );
    });

    test('deferToEnabledDay is a no-op when all days are enabled', () {
      final proposed = DateTime(2026, 7, 27, 15, 30); // Monday
      expect(
        RA_WeekdaySchedule.deferToEnabledDay(
          proposed,
          RA_WeekdaySchedule.allDaysMask,
        ),
        proposed,
      );
    });

    test('deferToEnabledDay resumes at local day-start on next enabled day', () {
      // Wednesday 15:30; Mon–Fri only (bits 0..4).
      const weekdays = 0x1F;
      final wed = DateTime(2026, 7, 29, 15, 30);
      expect(wed.weekday, DateTime.wednesday);
      expect(RA_WeekdaySchedule.deferToEnabledDay(wed, weekdays), wed);

      final sat = DateTime(2026, 8, 1, 9, 0); // Saturday
      expect(sat.weekday, DateTime.saturday);
      final mondayMidnight = RA_WeekdaySchedule.deferToEnabledDay(
        sat,
        weekdays,
        dayStartSeconds: 0,
      );
      expect(mondayMidnight, DateTime(2026, 8, 3, 0, 0)); // Monday 12:00 AM
      expect(mondayMidnight.isUtc, isFalse);
      expect(mondayMidnight.hour, 0);
      expect(mondayMidnight.minute, 0);

      final mondaySix = RA_WeekdaySchedule.deferToEnabledDay(
        sat,
        weekdays,
        dayStartSeconds: 6 * 3600,
      );
      expect(mondaySix, DateTime(2026, 8, 3, 6, 0));
      expect(mondaySix.isUtc, isFalse);
    });

    test('deferToEnabledDay wraps the weekend for a single-day mask', () {
      const fridayOnly = 1 << 4;
      final saturday = DateTime(2026, 8, 1, 8, 15);
      expect(
        RA_WeekdaySchedule.deferToEnabledDay(saturday, fridayOnly),
        DateTime(2026, 8, 7, 0, 0), // next Friday local midnight
      );
    });

    test('deferToEnabledDay treats zero mask as all days', () {
      final proposed = DateTime(2026, 7, 27, 12);
      expect(RA_WeekdaySchedule.deferToEnabledDay(proposed, 0), proposed);
    });

    test('isEveryDay treats zero and allDaysMask the same', () {
      expect(RA_WeekdaySchedule.isEveryDay(0), isTrue);
      expect(RA_WeekdaySchedule.isEveryDay(RA_WeekdaySchedule.allDaysMask), isTrue);
      expect(RA_WeekdaySchedule.isEveryDay(0x1F), isFalse);
    });

    test('summaryLabel covers every day, range, and sparse sets', () {
      expect(
        RA_WeekdaySchedule.summaryLabel(RA_WeekdaySchedule.allDaysMask),
        'Every day',
      );
      expect(RA_WeekdaySchedule.summaryLabel(0x1F), 'Mon to Fri');
      expect(RA_WeekdaySchedule.summaryLabel(1 << 0), 'Mon');
      expect(RA_WeekdaySchedule.summaryLabel(0x15), 'MWF'); // Mon, Wed, Fri
    });
  });
}
