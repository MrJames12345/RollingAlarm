import 'package:drift/drift.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/daily_ring_limit.dart';
import 'package:rolling_alarm/services/widget.dart';

/// Duplicates an existing routine with a fresh schedule and counter state.
class RA_RoutineDuplicateService {
  RA_RoutineDuplicateService._();

  static const _copySuffix = ' (Copy)';
  static const _maxNameLength = 255;

  static String copyName(String sourceName) {
    if (sourceName.length + _copySuffix.length <= _maxNameLength) {
      return '$sourceName$_copySuffix';
    }
    return '${sourceName.substring(0, _maxNameLength - _copySuffix.length)}$_copySuffix';
  }

  static RoutinesCompanion companionFrom(RoutineModel source) {
    return RoutinesCompanion(
      Name: Value(copyName(source.Name)),
      IntervalSeconds: Value(source.IntervalSeconds),
      SnoozeSeconds: Value(source.SnoozeSeconds),
      MaxTimesPerDayEnabled: Value(source.MaxTimesPerDayEnabled),
      MaxTimesPerDay: Value(source.MaxTimesPerDay),
      DayStartSeconds: Value(source.DayStartSeconds),
      EnabledWeekdays: Value(source.EnabledWeekdays),
      DriftCompensationTypeCode: Value(source.DriftCompensationTypeCode),
      ShowPreview: Value(source.ShowPreview),
      Vibrate: Value(source.Vibrate),
      Volume: Value(source.Volume),
      FadeIn: Value(source.FadeIn),
      AudioUri: Value(source.AudioUri),
    );
  }

  /// Creates a new routine with the same config as [source] and a fresh schedule.
  static Future<int> duplicate({
    required RA_Database db,
    required RoutineModel source,
    required String dbPath,
  }) async {
    final companion = companionFrom(source);
    final nextTrigger = RA_DailyRingLimit.initialTriggerTime(
      now: DateTime.now(),
      interval: Duration(seconds: source.IntervalSeconds),
      maxTimesPerDayEnabled: source.MaxTimesPerDayEnabled,
      dayStartSeconds: source.DayStartSeconds,
      enabledWeekdays: source.EnabledWeekdays,
    );
    final routineId = await db.insertRoutineWithInitialState(
      routine: companion,
      nextTriggerTime: nextTrigger,
    );
    await RA_AlarmService.scheduleNext(
      routineId: routineId,
      triggerTime: nextTrigger,
      dbPath: dbPath,
      routineName: companion.Name.value,
      refreshWidget: false,
    );
    await RA_WidgetService.updateWidgetState(db: db);
    return routineId;
  }
}
