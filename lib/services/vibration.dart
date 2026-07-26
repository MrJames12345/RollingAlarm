import 'dart:io';

import 'package:flutter/services.dart';

/// Repeating device vibration while an alarm is ringing.
class RA_VibrationService {
  RA_VibrationService._();

  static const MethodChannel _channel = MethodChannel(
    'com.example.rolling_alarm/alarm_ui_scheduler',
  );

  /// Starts a repeating vibrate / pause pattern.
  static Future<void> start() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      await _channel.invokeMethod<void>('startVibration');
    } catch (_) {
      // Vibration is best effort.
    }
  }

  /// Stops any active alarm vibration.
  static Future<void> stop() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      await _channel.invokeMethod<void>('stopVibration');
    } catch (_) {
      // Vibration is best effort.
    }
  }
}
