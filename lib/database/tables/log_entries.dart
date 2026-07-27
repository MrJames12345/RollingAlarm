import 'package:drift/drift.dart';

/// LogEntries table, recording every alarm lifecycle event.
/// Generates [LogEntryModel] via @DataClassName.
@DataClassName('LogEntryModel')
class LogEntries extends Table {
  IntColumn get Id => integer().autoIncrement()();
  IntColumn get RoutineId => integer()();
  DateTimeColumn get Timestamp => dateTime()();
  IntColumn get LogActionTypeCode => integer()();
  IntColumn get TimeSinceLastDismissalSeconds => integer().nullable()();

  /// True when this event was produced by a muted auto dismiss (no ring UX).
  BoolColumn get WasMuted => boolean().withDefault(const Constant(false))();

  // Audit columns
  DateTimeColumn get CreatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get ModifiedAt => dateTime().nullable()();
  BoolColumn get Deleted => boolean().withDefault(const Constant(false))();
}
