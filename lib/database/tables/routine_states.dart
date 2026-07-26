import 'package:drift/drift.dart';

/// RoutineStates table, tracking the current alarm cycle state for each routine.
/// Generates [RoutineStateModel] via @DataClassName.
@DataClassName('RoutineStateModel')
class RoutineStates extends Table {
  IntColumn get Id => integer().autoIncrement()();
  IntColumn get RoutineId => integer()();
  DateTimeColumn get NextTriggerTime => dateTime().nullable()();
  DateTimeColumn get InitialRingTime => dateTime().nullable()();
  IntColumn get CurrentSnoozeCount =>
      integer().withDefault(const Constant(0))();
  /// Fresh rings that counted toward [Routines.MaxTimesPerDay] for [TimesRingDay].
  IntColumn get TimesRingToday => integer().withDefault(const Constant(0))();
  /// Start of the day period that [TimesRingToday] applies to.
  DateTimeColumn get TimesRingDay => dateTime().nullable()();
  BoolColumn get IsRinging => boolean().withDefault(const Constant(false))();
  DateTimeColumn get LastDismissedAt => dateTime().nullable()();

  // Audit columns
  DateTimeColumn get CreatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get ModifiedAt => dateTime().nullable()();
  BoolColumn get Deleted => boolean().withDefault(const Constant(false))();

  /// One live state row per routine. Prevents duplicate inserts from racing
  /// isolate writers from breaking [getSingleOrNull] / [watchSingleOrNull].
  @override
  List<Set<Column>> get uniqueKeys => [
        {RoutineId},
      ];
}
