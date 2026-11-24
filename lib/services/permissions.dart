import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/components/common/oem_battery_guide_sheet.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/notification.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Live snapshot of alarm reliability permissions on the current device.
class RA_AlarmPermissionStatus {
  final bool notificationsGranted;
  final bool exactAlarmsGranted;
  final bool fullScreenIntentGranted;
  final bool unrestrictedBatteryGranted;
  final bool displayOverAppsGranted;

  const RA_AlarmPermissionStatus({
    required this.notificationsGranted,
    required this.exactAlarmsGranted,
    required this.fullScreenIntentGranted,
    required this.unrestrictedBatteryGranted,
    required this.displayOverAppsGranted,
  });
}

/// Contextual alarm permission onboarding and live status helpers.
///
/// Replaces cold-start permission bombing and per-schedule battery settings
/// redirects with contextual prompts on first alarm arming plus manual 1-tap
/// controls in Settings.
class RA_PermissionService {
  RA_PermissionService._();

  static const MethodChannel _uiSchedulerChannel = MethodChannel(
    'com.casellaweb.rolling_alarm/alarm_ui_scheduler',
  );

  static const String _notifPromptedKey = 'ra_perm_notif_prompted';
  static const String _fsiPromptedKey = 'ra_perm_fsi_prompted';
  static const String oemBatteryPromptedKey = 'ra_perm_oem_battery_prompted';

  /// Test-only override to exercise the post-first-save OEM battery sheet inside
  /// `flutter test` where `FLUTTER_TEST` is normally set in the environment.
  @visibleForTesting
  static bool? debugAllowOemSheetInTests;

  /// Requests only the core permissions required for alarms to fire and wake
  /// the lock screen, called contextually when the user saves, imports,
  /// duplicates, resumes, or recovers a routine.
  static Future<void> ensureCoreAlarmPermissions(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Notification permission (requested once when not yet granted).
      final notifGranted = await isNotificationGranted();
      if (!notifGranted && prefs.getBool(_notifPromptedKey) != true) {
        await prefs.setBool(_notifPromptedKey, true);
        try {
          await Permission.notification.request();
        } catch (_) {}
      }

      // 2. Exact alarm capability (request SCHEDULE_EXACT_ALARM only on API 31-32
      //    when denied; API 33+ uses install-time USE_EXACT_ALARM).
      final sdkInt = await getAndroidSdkInt();
      if (sdkInt >= 31 && sdkInt <= 32) {
        final exactAllowed = await canScheduleExactAlarms();
        if (!exactAllowed) {
          try {
            final status = await Permission.scheduleExactAlarm.status;
            if (!status.isGranted) {
              await Permission.scheduleExactAlarm.request();
            }
          } catch (_) {}
        }
      }

      // 3. Android 14+ full-screen intent: explain lock-screen wake once with a
      //    themed in-app dialog before opening special app access settings.
      if (sdkInt >= 34) {
        final fsiGranted = await canUseFullScreenIntent();
        if (!fsiGranted && prefs.getBool(_fsiPromptedKey) != true) {
          if (!context.mounted) return;
          await prefs.setBool(_fsiPromptedKey, true);
          if (!context.mounted) return;
          final shouldOpen = await _showFullScreenIntentDialog(context);
          if (shouldOpen == true) {
            await RA_NotificationService.requestFullScreenIntentPermission();
          }
        }
      }

      // 4. Post-first-save OEM battery reliability guide: shown once when not
      //    yet exempt from battery optimizations (skipped in widget/integration
      //    tests or when the native channel is absent).
      final allowOemSheet =
          debugAllowOemSheetInTests ??
          !Platform.environment.containsKey('FLUTTER_TEST');
      if (allowOemSheet && prefs.getBool(oemBatteryPromptedKey) != true) {
        final batteryExempt = await isIgnoringBatteryOptimizations();
        if (!batteryExempt) {
          final manufacturer = await _getDeviceManufacturerRaw();
          if (manufacturer != null && context.mounted) {
            await prefs.setBool(oemBatteryPromptedKey, true);
            if (!context.mounted) return;
            await RA_OemBatteryGuideSheet.show(
              context,
              manufacturer: manufacturer,
            );
          }
        }
      }
    } catch (_) {
      // Missing plugins / headless test environments fail soft.
    }
  }

  /// Opens the manufacturer-tailored battery guide bottom sheet on demand
  /// (used from Settings -> Alarm Reliability).
  static Future<void> showOemBatteryGuide(BuildContext context) async {
    final manufacturer = await getDeviceManufacturer();
    if (!context.mounted) return;
    await RA_OemBatteryGuideSheet.show(context, manufacturer: manufacturer);
  }

  /// Reads lowercased `android.os.Build.MANUFACTURER` via native channel
  /// (`''` when absent).
  static Future<String> getDeviceManufacturer() async {
    return (await _getDeviceManufacturerRaw()) ?? '';
  }

  static Future<String?> _getDeviceManufacturerRaw() async {
    try {
      final result = await _uiSchedulerChannel.invokeMethod<String>(
        'getDeviceManufacturer',
      );
      return result?.trim().toLowerCase();
    } catch (_) {
      return null;
    }
  }

  /// Whether POST_NOTIFICATIONS is currently granted.
  static Future<bool> isNotificationGranted() async {
    try {
      final status = await Permission.notification.status;
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Whether the OS currently allows scheduling exact alarms.
  static Future<bool> canScheduleExactAlarms() async {
    try {
      final result = await _uiSchedulerChannel.invokeMethod<bool>(
        'canScheduleExactAlarms',
      );
      if (result != null) return result;
    } catch (_) {}
    try {
      return (await Permission.scheduleExactAlarm.status).isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Whether full-screen alarm intents can display over the lock screen.
  /// Returns `true` on Android 13 and below where no separate toggle exists.
  static Future<bool> canUseFullScreenIntent() async {
    try {
      final result = await _uiSchedulerChannel.invokeMethod<bool>(
        'canUseFullScreenIntent',
      );
      if (result != null) return result;
    } catch (_) {}
    return true;
  }

  /// Whether the app is exempt from Doze / OEM battery optimizations.
  static Future<bool> isIgnoringBatteryOptimizations() {
    return RA_AlarmService.isIgnoringBatteryOptimizations();
  }

  /// Whether Display Over Other Apps (SYSTEM_ALERT_WINDOW) is granted.
  static Future<bool> isDisplayOverAppsGranted() async {
    try {
      final status = await Permission.systemAlertWindow.status;
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Reads Android `Build.VERSION.SDK_INT` via native channel (`0` when absent).
  static Future<int> getAndroidSdkInt() async {
    try {
      final result = await _uiSchedulerChannel.invokeMethod<int>(
        'getAndroidSdkInt',
      );
      return result ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Fetches live status across all alarm reliability permissions.
  static Future<RA_AlarmPermissionStatus> getStatus() async {
    final results = await Future.wait<bool>([
      isNotificationGranted(),
      canScheduleExactAlarms(),
      canUseFullScreenIntent(),
      isIgnoringBatteryOptimizations(),
      isDisplayOverAppsGranted(),
    ]);
    return RA_AlarmPermissionStatus(
      notificationsGranted: results[0],
      exactAlarmsGranted: results[1],
      fullScreenIntentGranted: results[2],
      unrestrictedBatteryGranted: results[3],
      displayOverAppsGranted: results[4],
    );
  }

  static Future<bool?> _showFullScreenIntentDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        backgroundColor: RA_ColourStyles.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: RA_ShapeStyles.largeBorderRadius,
        ),
        title: Text('Lock-Screen Alarm Alerts', style: RA_TextStyles.mediumFont),
        content: Text(
          'On Android 14 and newer, Rolling Alarm needs Full-Screen Alert access to wake your screen and show snooze and dismiss controls over your lock screen when an alarm rings.',
          style: RA_TextStyles.smallFont.copyWith(height: 1.35),
        ),
        actions: [
          RA_DialogButton('Not Now', () => Navigator.pop(ctx, false)),
          RA_DialogButton(
            'Open Settings',
            () => Navigator.pop(ctx, true),
            color: RA_ColourStyles.secondary,
          ),
        ],
      ),
    );
  }
}
