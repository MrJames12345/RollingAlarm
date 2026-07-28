import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/services/daily_ring_limit.dart';
import 'package:rolling_alarm/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Syncs routine dashboard fields to every home screen widget instance.
///
/// Each Android widget stores its own `routine_id` (chosen in the configure
/// activity). This service writes display strings keyed by routine id into the
/// home_widget SharedPreferences bridge, then asks Glance to redraw.
class RA_WidgetService {
  RA_WidgetService._();

  /// Fully qualified Glance AppWidgetProvider / receiver class name.
  ///
  /// Must be passed as [HomeWidget.updateWidget]'s [qualifiedAndroidName].
  /// Using [androidName] with a package prefixed string makes home_widget look
  /// up `package.package.Class` and the redraw never runs.
  static const String _appWidgetProvider =
      'com.example.rolling_alarm.RollingAlarmWidgetReceiver';

  static const String _uiSchedulerChannel =
      'com.example.rolling_alarm/alarm_ui_scheduler';

  /// Absolute clock time for the widget (e.g. "07:30 AM"), never a countdown.
  static final DateFormat _alarmClockFormat = DateFormat('hh:mm a');

  /// Recalculates and pushes active routine state to the native widget bridge.
  ///
  /// For each non-deleted active routine, writes:
  /// * `routine_{id}_name`
  /// * `routine_{id}_next_alarm_time`
  /// * `routine_{id}_interval_time`
  /// * `routine_{id}_dismissals_today`
  ///
  /// Safe to call from the UI isolate or a background alarm isolate. When [db]
  /// is omitted, opens a short-lived isolate connection from the persisted path.
  ///
  /// Call after snooze, dismiss, skip, schedule, and routine edits so next
  /// alarm time and dismissals today stay in sync on the home screen.
  static Future<void> updateWidgetState({RA_Database? db}) async {
    RA_Database? owned;
    try {
      final database = db ?? await _openDbFromPrefs();
      if (db == null) owned = database;
      if (database == null) {
        await _requestWidgetRedraw();
        return;
      }

      final routines = await database.getActiveRoutines();
      final now = DateTime.now();

      for (final routine in routines) {
        final state = await database.getRoutineState(routine.Id);
        final periodStart = RA_DailyRingLimit.periodStart(
          now,
          routine.DayStartSeconds,
        );
        final dismissals = await database.countDismissalsSince(
          routineId: routine.Id,
          since: periodStart,
        );
        final next = state?.NextTriggerTime;
        final nextAlarmTime = next != null
            ? _alarmClockFormat.format(next)
            : '--:--';

        await HomeWidget.saveWidgetData<String>(
          'routine_${routine.Id}_name',
          routine.Name,
        );
        await HomeWidget.saveWidgetData<String>(
          'routine_${routine.Id}_next_alarm_time',
          nextAlarmTime,
        );
        await HomeWidget.saveWidgetData<String>(
          'routine_${routine.Id}_interval_time',
          RA_Utils.formatInterval(routine.IntervalSeconds),
        );
        await HomeWidget.saveWidgetData<String>(
          'routine_${routine.Id}_dismissals_today',
          dismissals.toString(),
        );
      }

      await _requestWidgetRedraw();
    } catch (_) {
      // Ignore widget update failures in unit tests or headless isolates.
    } finally {
      await owned?.close();
    }
  }

  /// Asks Android to redraw every Glance instance.
  ///
  /// Uses both home_widget's AppWidget broadcast (works in alarm isolates where
  /// the plugin is registered) and the native Glance [WidgetRefresh] path
  /// (bumps preferences so composition cannot stay stale).
  static Future<void> _requestWidgetRedraw() async {
    try {
      await HomeWidget.updateWidget(qualifiedAndroidName: _appWidgetProvider);
    } catch (_) {}
    try {
      const channel = MethodChannel(_uiSchedulerChannel);
      await channel.invokeMethod<void>('refreshWidgets');
    } catch (_) {}
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
