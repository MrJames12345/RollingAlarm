import 'package:drift/drift.dart';

/// Routines table, defining each alarm routine's configuration.
/// Generates [RoutineModel] via @DataClassName.
@DataClassName('RoutineModel')
class Routines extends Table {
  IntColumn get Id => integer().autoIncrement()();
  TextColumn get Name => text().withLength(min: 1, max: 255)();

  /// Duration of snooze in total seconds.
  IntColumn get SnoozeSeconds => integer().withDefault(const Constant(300))();

  /// Total repeating interval length in seconds.
  IntColumn get IntervalSeconds => integer()();

  /// Max fresh rings per day period when [MaxTimesPerDayEnabled] is true.
  IntColumn get MaxTimesPerDay => integer().withDefault(const Constant(0))();

  /// Seconds after local midnight when the daily ring counter resets.
  IntColumn get DayStartSeconds => integer().withDefault(const Constant(0))();

  /// When false, daily ring cap fields are ignored (unlimited rings).
  BoolColumn get MaxTimesPerDayEnabled =>
      boolean().withDefault(const Constant(false))();
  IntColumn get DriftCompensationTypeCode => integer()();
  BoolColumn get ShowPreview => boolean().withDefault(const Constant(true))();

  /// When true, the device vibrates while this routine's alarm is ringing.
  BoolColumn get Vibrate => boolean().withDefault(const Constant(true))();

  /// Alarm playback volume from 0 (silent) to 100 (full).
  IntColumn get Volume => integer().withDefault(const Constant(100))();

  /// When true, alarm audio fades from silent up to [Volume] on trigger.
  BoolColumn get FadeIn => boolean().withDefault(const Constant(false))();
  TextColumn get AudioUri => text().nullable()();
  BoolColumn get IsActive => boolean().withDefault(const Constant(true))();

  // Audit columns (BaseModel pattern)
  DateTimeColumn get CreatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get ModifiedAt => dateTime().nullable()();
  BoolColumn get Deleted => boolean().withDefault(const Constant(false))();
}
