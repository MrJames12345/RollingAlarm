import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/alarm_action_type_code.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Top-level background handler required by flutter_local_notifications.
@pragma('vm:entry-point')
Future<void> raNotificationBackgroundHandler(
  NotificationResponse response,
) async {
  await RA_NotificationService.handleNotificationResponse(response);
}

/// Manages local notifications including full-screen intent for alarm ring.
class RA_NotificationService {
  RA_NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Long-lived UI-isolate database from [main]. Prefer this over opening a
  /// second sync [NativeDatabase] when notification actions fire in foreground.
  static RA_Database? _uiDatabase;

  /// v2: bypass DND + max importance. New id so existing installs pick up
  /// channel settings that Android freezes after first create.
  static const String _channelId = 'ra_alarm_channel_v2';
  static const String _channelName = 'Alarm';
  static const String _channelDesc =
      'Full-screen alarm alerts when a Rolling Alarm is ringing';
  static const String _actionSnooze = 'snooze';
  static const String _actionDismiss = 'dismiss';

  /// SharedPreferences key mirrored into MainActivity for lock-screen flags
  /// before Flutter finishes booting (full-screen intent cold start).
  static const String ringingPrefKey = 'ra_is_ringing';
  static const String alarmWakeAtPrefKey = 'ra_alarm_wake_at_ms';

  /// Binds the ProviderScope / main-isolate [RA_Database] for foreground
  /// notification action handling. Call once from [main] after path resolve.
  static void bindUiDatabase(RA_Database database) {
    _uiDatabase = database;
  }

  /// Initialises the notification plugin. Call once from main().
  static Future<void> init() async {
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);

      await _plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: handleNotificationResponse,
        onDidReceiveBackgroundNotificationResponse:
            raNotificationBackgroundHandler,
      );

      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.max,
          playSound: false,
          enableVibration: true,
          bypassDnd: true,
        ),
      );
    } catch (_) {
      // Ignore notification plugin init errors in headless test environments
    }
  }

  /// Requests Android 14+ full-screen intent special access when needed.
  ///
  /// [USE_FULL_SCREEN_INTENT] is declared in the manifest; on API 34+ the OS
  /// may still require an app-ops grant via Settings. No-ops on older APIs /
  /// non-Android / headless test hosts.
  static Future<void> requestFullScreenIntentPermission() async {
    try {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.requestFullScreenIntentPermission();
    } catch (_) {
      // Ignore permission request failures in headless test environments
    }
  }

  /// Posts a high-importance full-screen-intent notification so Android can
  /// launch [MainActivity] over the lock screen even when the UI process is
  /// dead (Google Clock pattern). Audio stays in [RA_AudioService].
  static Future<void> showAlarmNotification({
    required int routineId,
    required String routineName,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(ringingPrefKey, true);
      await prefs.setInt(
        alarmWakeAtPrefKey,
        DateTime.now().millisecondsSinceEpoch,
      );

      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        fullScreenIntent: true,
        ongoing: true,
        autoCancel: false,
        playSound: false,
        enableVibration: true,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            _actionSnooze,
            'Snooze',
            showsUserInterface: false,
            cancelNotification: false,
          ),
          AndroidNotificationAction(
            _actionDismiss,
            'Dismiss',
            showsUserInterface: false,
            cancelNotification: false,
          ),
        ],
      );

      await _plugin.show(
        id: routineId,
        title: routineName,
        body: 'Alarm is ringing',
        notificationDetails: const NotificationDetails(android: androidDetails),
        payload: '$routineId',
      );
    } catch (_) {
      // Never let notification failure block audio / UI wake paths.
    }
  }

  /// Cancels the alarm notification for the given routine.
  static Future<void> cancelNotification(int routineId) async {
    try {
      await _plugin.cancel(id: routineId);
      await RA_AlarmService.stopNativeRinging(routineId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(ringingPrefKey, false);
      await prefs.remove(alarmWakeAtPrefKey);
    } catch (_) {
      // Ignore notification cancel errors in headless test environments
    }
  }

  /// Clears the lock-screen ringing preference without cancelling a specific id.
  static Future<void> clearRingingPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(ringingPrefKey, false);
      await prefs.remove(alarmWakeAtPrefKey);
    } catch (_) {}
  }

  /// Handles Snooze / Dismiss notification actions from foreground or background.
  ///
  /// Foreground (main isolate) reuses [bindUiDatabase] when set so we do not
  /// open a second sync [NativeDatabase] beside [NativeDatabase.createInBackground].
  /// True headless entry points fall back to [RA_Database.openForIsolate].
  static Future<void> handleNotificationResponse(
    NotificationResponse response,
  ) async {
    final actionId = response.actionId;
    if (actionId != _actionSnooze && actionId != _actionDismiss) {
      return;
    }

    final routineId = int.tryParse(response.payload ?? '');
    if (routineId == null) return;

    final action = actionId == _actionSnooze
        ? RA_AlarmActionTypeCodeEnum.Snooze
        : RA_AlarmActionTypeCodeEnum.Dismiss;

    try {
      final prefs = await SharedPreferences.getInstance();
      final dbPath = prefs.getString('ra_db_path');
      if (dbPath == null) return;

      final uiDb = _uiDatabase;
      final ownsConnection = uiDb == null;
      final db = uiDb ?? RA_Database.openForIsolate(dbPath);
      try {
        final routine = await db.getRoutineById(routineId);
        final state = await db.getRoutineState(routineId);
        if (state == null) return;

        await RA_AudioService.stopAlarm();
        await RA_AlarmService.handleTransition(
          action: action,
          routineId: routineId,
          db: db,
          routine: routine,
          state: state,
        );
        await cancelNotification(routineId);
      } finally {
        if (ownsConnection) {
          await db.close();
        }
      }
    } catch (_) {
      // Ignore action handling failures in headless or race conditions
    }
  }
}
