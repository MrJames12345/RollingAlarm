import 'dart:io';

import 'package:flutter/services.dart';

/// Native [Ringtone] playback for system device sounds.
///
/// RingtoneManager content:// URIs are not reliable through just_audio setUrl;
/// this channel plays them with Android Ringtone + USAGE_ALARM.
/// Loudness is controlled by [AudioManager.STREAM_ALARM], not Ringtone gain.
class RA_DeviceRingtone {
  RA_DeviceRingtone._();

  static const MethodChannel _channel = MethodChannel(
    'com.example.rolling_alarm/alarm_sound',
  );

  /// Plays [uri] via the platform Ringtone API.
  ///
  /// Returns `true` when playback started, `false` when the URI failed to
  /// play, and `null` when the platform channel is unavailable (headless
  /// isolate without MainActivity).
  ///
  /// [volume] is internal Ringtone gain (0.0 to 1.0). Peak loudness still
  /// comes from [AudioManager.STREAM_ALARM]. When [fadeInMs] is positive,
  /// gain ramps from 0 to [volume].
  static Future<bool?> play({
    required String uri,
    bool loop = true,
    bool asAlarm = true,
    int fadeInMs = 0,
    double volume = 1.0,
  }) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return true;
    }
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      final started = await _channel
          .invokeMethod<bool>('playDeviceSound', <String, dynamic>{
            'uri': uri,
            'loop': loop,
            'asAlarm': asAlarm,
            'fadeInMs': fadeInMs,
            'volume': volume.clamp(0.0, 1.0),
          });
      return started ?? false;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Stops any native device ringtone started by [play].
  static Future<void> stop() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('stopDeviceSound');
    } catch (_) {
      // Channel may be absent in headless isolates.
    }
  }
}
