import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_alarm/utils.dart';

void main() {
  group('RA_tryAsync', () {
    test('returns value when action succeeds', () async {
      expect(await RA_tryAsync(() async => 7), 7);
    });

    test('returns null when action throws', () async {
      expect(
        await RA_tryAsync<int>(() async => throw StateError('boom')),
        isNull,
      );
    });
  });

  group('RA_Utils', () {
    test('formatDuration includes hours when present', () {
      expect(
        RA_Utils.formatDuration(const Duration(hours: 4, minutes: 30)),
        '4h 30m',
      );
    });

    test('formatDuration omits hours when zero', () {
      expect(RA_Utils.formatDuration(const Duration(minutes: 9)), '9m');
    });

    test('formatDuration includes seconds when present', () {
      expect(
        RA_Utils.formatDuration(
          const Duration(hours: 1, minutes: 2, seconds: 3),
        ),
        '1h 2m 3s',
      );
      expect(RA_Utils.formatDuration(const Duration(seconds: 45)), '45s');
    });

    test('formatDuration formats empty duration as 0s', () {
      expect(RA_Utils.formatDuration(Duration.zero), '0s');
    });

    test('formatCountdown pads HH:MM:SS', () {
      expect(
        RA_Utils.formatCountdown(
          const Duration(hours: 1, minutes: 2, seconds: 3),
        ),
        '01:02:03',
      );
    });

    test('formatCountdown clamps negative durations to zeros', () {
      expect(RA_Utils.formatCountdown(const Duration(seconds: -5)), '00:00:00');
    });

    test('formatDateTime uses readable month day year time', () {
      final dt = DateTime(2026, 1, 1, 6, 0);
      expect(RA_Utils.formatDateTime(dt), 'Jan 1, 2026 6:00 AM');
    });

    test('formatTime returns clock time only', () {
      final dt = DateTime(2026, 7, 25, 18, 45);
      expect(RA_Utils.formatTime(dt), '6:45 PM');
    });

    test('formatClock zero-pads hour and includes seconds', () {
      final dt = DateTime(2026, 7, 25, 18, 45, 7);
      expect(RA_Utils.formatClock(dt), '06:45:07 PM');
    });

    test('formatSecondsAsDuration delegates to formatDuration', () {
      expect(RA_Utils.formatSecondsAsDuration(16200), '4h 30m');
    });

    test('formatInterval builds duration from total seconds', () {
      expect(RA_Utils.formatInterval(4 * 3600 + 30 * 60), '4h 30m');
      expect(RA_Utils.formatInterval(15 * 60), '15m');
      expect(RA_Utils.formatInterval(45), '45s');
    });
  });
}
