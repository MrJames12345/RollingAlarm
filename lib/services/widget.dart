import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/services/daily_ring_limit.dart';
import 'package:rolling_alarm/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the single Android home screen widget: pin selection and state sync.
class RA_WidgetService {
  RA_WidgetService._();

  static const String _appWidgetProvider =
      'com.example.rolling_alarm.RollingAlarmWidgetReceiver';

  static const String _pinnedRoutineIdKey = 'ra_widget_pinned_routine_id';

  /// Absolute clock time for the widget (e.g. "07:30 AM"), never a countdown.
  static final DateFormat _alarmClockFormat = DateFormat('hh:mm a');

  /// Returns the routine id pinned to the home widget, or null if none.
  static Future<int?> getPinnedRoutineId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_pinnedRoutineIdKey);
    } catch (_) {
      return null;
    }
  }

  /// Pins [routineId] to the widget, or clears the pin when null.
  static Future<void> setPinnedRoutineId(int? routineId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (routineId == null) {
        await prefs.remove(_pinnedRoutineIdKey);
      } else {
        await prefs.setInt(_pinnedRoutineIdKey, routineId);
      }
    } catch (_) {
      // Ignore preference failures in unit tests / headless isolates.
    }
  }

  /// Clears the pin when it matches [routineId] (e.g. after soft delete).
  static Future<void> clearPinnedRoutineIfMatch(int routineId) async {
    final pinned = await getPinnedRoutineId();
    if (pinned == routineId) {
      await setPinnedRoutineId(null);
    }
  }

  /// Recalculates and pushes pinned routine state to the native widget bridge.
  ///
  /// Writes exactly:
  /// * `routine_name`
  /// * `next_alarm_time` (absolute clock time, e.g. "07:30 AM")
  /// * `interval_time` (e.g. "15m")
  /// * `dismissals_today`
  ///
  /// Safe to call from the UI isolate or a background alarm isolate. When [db]
  /// is omitted, opens a short-lived isolate connection from the persisted path.
  static Future<void> updateWidgetState({RA_Database? db}) async {
    RA_Database? owned;
    try {
      final database = db ?? await _openDbFromPrefs();
      if (db == null) owned = database;
      if (database == null) {
        await _writeEmptyWidgetState();
        return;
      }

      final pinnedId = await getPinnedRoutineId();
      if (pinnedId == null) {
        await _writeEmptyWidgetState();
        return;
      }

      final routine = await database.getRoutineById(pinnedId);
      if (routine.Deleted || !routine.IsActive) {
        await setPinnedRoutineId(null);
        await _writeEmptyWidgetState();
        return;
      }

      final state = await database.getRoutineState(pinnedId);
      final now = DateTime.now();
      final periodStart = RA_DailyRingLimit.periodStart(
        now,
        routine.DayStartSeconds,
      );
      final dismissals = await database.countDismissalsSince(
        routineId: pinnedId,
        since: periodStart,
      );

      final next = state?.NextTriggerTime;
      final nextAlarmTime =
          next != null ? _alarmClockFormat.format(next) : '--:--';

      await HomeWidget.saveWidgetData<String>('routine_name', routine.Name);
      await HomeWidget.saveWidgetData<String>(
        'next_alarm_time',
        nextAlarmTime,
      );
      await HomeWidget.saveWidgetData<String>(
        'interval_time',
        RA_Utils.formatInterval(routine.IntervalSeconds),
      );
      await HomeWidget.saveWidgetData<String>(
        'dismissals_today',
        dismissals.toString(),
      );

      await HomeWidget.updateWidget(androidName: _appWidgetProvider);
    } catch (_) {
      // Ignore widget update failures in unit tests or headless isolates.
    } finally {
      await owned?.close();
    }
  }

  static Future<void> _writeEmptyWidgetState() async {
    await HomeWidget.saveWidgetData<String>('routine_name', 'No Routine');
    await HomeWidget.saveWidgetData<String>('next_alarm_time', '--:--');
    await HomeWidget.saveWidgetData<String>('interval_time', '--');
    await HomeWidget.saveWidgetData<String>('dismissals_today', '0');
    await HomeWidget.updateWidget(androidName: _appWidgetProvider);
  }

  static Future<RA_Database?> _openDbFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dbPath = prefs.getString('ra_db_path');
      if (dbPath == null) return null;
      return RA_Database.openForIsolate(dbPath);
    } catch (_) {
      return null;
    }
  }
}
