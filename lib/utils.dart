import 'package:intl/intl.dart';

/// Awaits [action] and returns null if it throws.
///
/// Use at plugin / isolate / UI boundaries where failure must not cascade.
Future<T?> RA_tryAsync<T>(Future<T> Function() action) async {
  try {
    return await action();
  } catch (_) {
    return null;
  }
}

/// Shared formatting helpers for durations, countdowns, and timestamps.
class RA_Utils {
  RA_Utils._();

  /// Formats a [Duration] as compact units, e.g. "4h 30m", "15m 5s", "45s".
  /// Zero units are omitted; an empty duration formats as "0s".
  static String formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final parts = <String>[];
    if (h > 0) parts.add('${h}h');
    if (m > 0) parts.add('${m}m');
    if (s > 0 || parts.isEmpty) parts.add('${s}s');
    return parts.join(' ');
  }

  /// Formats a [Duration] as a countdown string "HH:MM:SS".
  static String formatCountdown(Duration d) {
    if (d.isNegative) return '00:00:00';
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// Formats a [DateTime] for display: "Jan 1, 2026 6:00 AM"
  static String formatDateTime(DateTime dt) =>
      DateFormat('MMM d, y h:mm a').format(dt);

  /// Formats a [DateTime] as time only: "6:00 AM"
  static String formatTime(DateTime dt) => DateFormat('h:mm a').format(dt);

  /// Fixed-width live clock with seconds: "06:00:00 AM".
  /// Zero-padded hour keeps tabular digits from shifting as time ticks.
  static String formatClock(DateTime dt) =>
      DateFormat('hh:mm:ss a').format(dt);

  /// Formats seconds into a human-readable duration string.
  static String formatSecondsAsDuration(int s) =>
      formatDuration(Duration(seconds: s));

  /// Returns the interval as a human-readable string from total seconds.
  static String formatInterval(int totalSeconds) =>
      formatDuration(Duration(seconds: totalSeconds));
}
