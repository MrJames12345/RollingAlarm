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

  /// Bonus daily cap additions for the current [TimesRingDay].
  IntColumn get ExtraMaxTimesToday => integer().withDefault(const Constant(0))();

  BoolColumn get IsRinging => boolean().withDefault(const Constant(false))();
  DateTimeColumn get LastDismissedAt => dateTime().nullable()();

  /// When set, the routine is paused: countdown freezes at
  /// [NextTriggerTime] minus this instant until resume.
  DateTimeColumn get PausedAt => dateTime().nullable()();

  /// When set, the routine is muted: schedule continues but fires are
  /// silently auto-dismissed and still count toward [TimesRingToday].
  DateTimeColumn get MutedAt => dateTime().nullable()();

  // Audit columns
  DateTimeColumn get CreatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get ModifiedAt => dateTime().nullable()();
  BoolColumn get Deleted => boolean().withDefault(const Constant(false))();

  /// One live state row per routine. Prevents duplicate inserts from racing
  /// isolate writers from breaking [getSingleOrNull] / [watchSingleOrNull].
  @override
  List<Set<Column>> get uniqueKeys => [
    {RoutineId},
  ];
}
