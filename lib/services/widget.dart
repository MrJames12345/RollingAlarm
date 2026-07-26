import 'package:home_widget/home_widget.dart';
import 'package:rolling_alarm/utils.dart';

/// Manages the Android home screen widget data and updates.
class RA_WidgetService {
  RA_WidgetService._();

  static const String _appWidgetProvider =
      'com.example.rolling_alarm.AlarmWidgetProvider';

  /// Updates the widget with the next trigger countdown, routine name, and id.
  static Future<void> updateWidget({
    required String routineName,
    required DateTime nextTriggerTime,
    int? routineId,
  }) async {
    try {
      await HomeWidget.saveWidgetData('routineName', routineName);
      await HomeWidget.saveWidgetData(
        'nextTriggerTime',
        nextTriggerTime.toIso8601String(),
      );
      await HomeWidget.saveWidgetData(
        'nextTriggerDisplay',
        RA_Utils.formatDateTime(nextTriggerTime),
      );
      if (routineId != null) {
        await HomeWidget.saveWidgetData('routineId', routineId.toString());
      }
      await HomeWidget.updateWidget(androidName: _appWidgetProvider);
    } catch (_) {
      // Ignore widget update failures in unit test environments or background isolates without context
    }
  }

  /// Registers the background callback for widget interactions (e.g. Skip).
  static Future<void> registerBackgroundCallback(
    Future<void> Function(Uri?) callback,
  ) async {
    try {
      await HomeWidget.registerInteractivityCallback(callback);
    } catch (_) {
      // Ignore callback registration errors in test environments
    }
  }
}
