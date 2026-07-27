/// Pure helpers for Monday-first weekday bitmasks on routines.
///
/// Bits 0..6 map to Mon..Sun, matching Dart [DateTime.weekday] 1..7 and the
/// edit-form label order MTWTFSS.
class RA_WeekdaySchedule {
  RA_WeekdaySchedule._();

  /// All seven days enabled.
  static const int allDaysMask = 0x7F;

  /// Single-letter labels in Monday-first order (MTWTFSS).
  static const List<String> dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  /// Bit index 0..6 for a Dart [DateTime.weekday] (1 = Mon … 7 = Sun).
  static int bitIndexForWeekday(int weekday) {
    assert(weekday >= 1 && weekday <= 7);
    return weekday - 1;
  }

  /// Whether [weekday] (Dart 1..7) is enabled in [mask].
  ///
  /// A zero [mask] is treated as all days (same as [deferToEnabledDay]).
  static bool isEnabled(int mask, int weekday) {
    final effective = mask == 0 ? allDaysMask : (mask & allDaysMask);
    final bit = 1 << bitIndexForWeekday(weekday);
    return (effective & bit) != 0;
  }

  /// Whether the calendar day of [dateTime] is enabled in [mask].
  static bool isDateEnabled(int mask, DateTime dateTime) =>
      isEnabled(mask, dateTime.weekday);

  /// Mask with [weekday] (Dart 1..7) toggled. Returns [mask] unchanged when
  /// turning off the last remaining day.
  static int toggleWeekday(int mask, int weekday) {
    final bit = 1 << bitIndexForWeekday(weekday);
    if ((mask & bit) != 0) {
      final next = mask & ~bit;
      if (next == 0) return mask;
      return next & allDaysMask;
    }
    return (mask | bit) & allDaysMask;
  }

  /// If [proposed] falls on a disabled weekday, return the same clock time on
  /// the next enabled calendar day. Unchanged when that day is enabled, or
  /// when [mask] has no bits set (treated as all days).
  static DateTime deferToEnabledDay(DateTime proposed, int mask) {
    final effective = mask == 0 ? allDaysMask : (mask & allDaysMask);
    if (effective == allDaysMask) return proposed;
    for (var i = 0; i < 7; i++) {
      final candidate = proposed.add(Duration(days: i));
      if (isDateEnabled(effective, candidate)) return candidate;
    }
    return proposed;
  }

  /// Compact summary label: "Every day", a contiguous range like "Mon to Fri",
  /// or the enabled letters (e.g. "MWF").
  static String summaryLabel(int mask) {
    final effective = mask == 0 ? allDaysMask : (mask & allDaysMask);
    if (effective == allDaysMask) return 'Every day';

    const shortNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final enabled = <int>[];
    for (var i = 0; i < 7; i++) {
      if ((effective & (1 << i)) != 0) enabled.add(i);
    }
    if (enabled.length == 1) return shortNames[enabled.first];

    final contiguous = enabled.last - enabled.first == enabled.length - 1;
    if (contiguous && enabled.length >= 2) {
      return '${shortNames[enabled.first]} to ${shortNames[enabled.last]}';
    }

    final buffer = StringBuffer();
    for (final i in enabled) {
      buffer.write(dayLabels[i]);
    }
    return buffer.toString();
  }
}
