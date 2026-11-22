import 'package:drift/drift.dart';

/// Key-value metadata persisted in SQLite for app-level flags such as v1.0.1
/// early-adopter grandfathering.
/// Generates [AppMetaModel] via @DataClassName.
@DataClassName('AppMetaModel')
class AppMeta extends Table {
  TextColumn get Key => text()();

  /// Persisted as SQLite column `value` (Dart identifier avoids shadowing Drift's `Value<T>`).
  TextColumn get MetaValue => text().named('value')();
  DateTimeColumn get UpdatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {Key};
}
