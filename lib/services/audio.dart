import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rolling_alarm/models/alarm_sound.dart';
import 'package:rolling_alarm/services/device_ringtone.dart';
import 'package:rolling_alarm/services/sound_preview.dart';
import 'package:rolling_alarm/services/vibration.dart';

/// Manages alarm audio playback on the Android alarm stream.
///
/// Peak loudness is set via [AudioManager.STREAM_ALARM] from [volume].
/// Optional [fadeIn] ramps internal player / Ringtone gain from 0 to 1.0 so
/// perceived loudness climbs up to that stream level.
class RA_AudioService {
  RA_AudioService._();

  static AudioPlayer? _player;
  static Timer? _fadeTimer;
  static ReceivePort? _controlPort;
  static StreamSubscription<dynamic>? _controlSub;

  static const String _audioPortName = 'ra_audio_control_port';
  static const String _alarmSoundChannel =
      'com.example.rolling_alarm/alarm_sound';

  /// Bundled fallback tone when a routine has no custom playable URI.
  static const String defaultAlarmAsset = 'assets/audio/default_alarm.wav';

  /// Duration over which fade-in climbs from silent to full internal gain.
  static const Duration fadeDuration = Duration(seconds: 10);
  static const int _fadeSteps = 20;

  /// Starts playing the alarm sound.
  ///
  /// [audioUri] may be a legacy plain URI or an encoded [RA_AlarmSound].
  /// When [vibrate] is true, starts repeating device vibration as well.
  /// [volume] is 0 to 100 and is applied to the OS alarm stream only.
  /// When [fadeIn] is true, internal gain starts at 0 and ramps to 1.0.
  static Future<void> startAlarm({
    String? audioUri,
    bool vibrate = true,
    int volume = 100,
    bool fadeIn = false,
  }) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }

    final systemVolume = (volume.clamp(0, 100) / 100.0);
    await _applySystemAlarmVolume(systemVolume);

    // If another isolate claimed audio but may be stuck (e.g. hung setUrl),
    // ask it to stop so this isolate (usually the ring UI) can take over.
    final existingPort = IsolateNameServer.lookupPortByName(_audioPortName);
    if (existingPort != null && _controlPort == null) {
      existingPort.send('stop');
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }

    try {
      await RA_SoundPreviewService.stop();
      await stopAlarm();

      if (vibrate) {
        await RA_VibrationService.start();
      }

      final sound = RA_AlarmSound.decode(audioUri);

      if (sound.isSilent) {
        _registerControlPort();
        return;
      }

      if (sound.usesNativeRingtone) {
        final started = await RA_DeviceRingtone.play(
          uri: sound.uri!.trim(),
          loop: true,
          asAlarm: true,
          fadeInMs: fadeIn ? fadeDuration.inMilliseconds : 0,
          volume: 1.0,
        );
        if (started == true) {
          _registerControlPort();
          return;
        }
        // Headless isolates lack MainActivity's channel. Leave audio for the
        // ring page instead of hanging on just_audio setUrl(content://...).
        if (started == null) {
          return;
        }
        // Native play failed with a live channel; fall through to default.
      }

      _registerControlPort();
      await _configureSession();

      _player = AudioPlayer();
      if (sound.hasPlayableUri) {
        await _player!.setUrl(sound.uri!);
      } else {
        await _player!.setAsset(defaultAlarmAsset);
      }
      await _player!.setLoopMode(LoopMode.one);
      await _player!.setVolume(fadeIn ? 0.0 : 1.0);
      await _player!.play();
      if (fadeIn) {
        _startFadeIn();
      }
    } catch (_) {
      // Primary source failed; try bundled default so the visual alarm still
      // has audio when possible.
      try {
        await RA_DeviceRingtone.stop();
        _registerControlPort();
        _player ??= AudioPlayer();
        await _player!.setAsset(defaultAlarmAsset);
        await _player!.setLoopMode(LoopMode.one);
        await _player!.setVolume(fadeIn ? 0.0 : 1.0);
        await _player!.play();
        if (fadeIn) {
          _startFadeIn();
        }
      } catch (_) {
        // Audio playback failed; continue visual alarm gracefully.
        await stopAlarm();
      }
    }
  }

  /// Stops the alarm audio and cleans up.
  static Future<void> stopAlarm() async {
    _fadeTimer?.cancel();
    _fadeTimer = null;

    await RA_VibrationService.stop();

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _player = null;
      return;
    }

    final sendPort = IsolateNameServer.lookupPortByName(_audioPortName);
    if (sendPort != null && _controlPort == null) {
      sendPort.send('stop');
    }

    IsolateNameServer.removePortNameMapping(_audioPortName);
    await _controlSub?.cancel();
    _controlPort?.close();
    _controlSub = null;
    _controlPort = null;

    await RA_DeviceRingtone.stop();

    try {
      await _player?.stop();
      await _player?.dispose();
    } catch (_) {
      // Ignore audio stop/dispose errors in test environments
    }
    _player = null;
  }

  static void _registerControlPort() {
    IsolateNameServer.removePortNameMapping(_audioPortName);
    unawaited(_controlSub?.cancel());
    _controlPort?.close();
    _controlSub = null;
    _controlPort = null;

    final port = ReceivePort();
    _controlPort = port;
    IsolateNameServer.registerPortWithName(port.sendPort, _audioPortName);
    _controlSub = port.listen((_) {
      unawaited(stopAlarm());
    });
  }

  /// Routes just_audio through Android USAGE_ALARM (STREAM_ALARM), not media.
  static Future<void> _configureSession() async {
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.sonification,
          usage: AndroidAudioUsage.alarm,
        ),
        androidAudioFocusGainType:
            AndroidAudioFocusGainType.gainTransientExclusive,
        androidWillPauseWhenDucked: false,
      ),
    );
  }

  /// Gradually increases internal player volume from 0 to 1 over [fadeDuration].
  static void _startFadeIn() {
    final stepDuration = fadeDuration ~/ _fadeSteps;
    int currentStep = 0;

    _fadeTimer?.cancel();
    _fadeTimer = Timer.periodic(stepDuration, (timer) {
      currentStep++;
      final volume = currentStep / _fadeSteps;
      final player = _player;
      if (player != null) {
        unawaited(player.setVolume(volume.clamp(0.0, 1.0)));
      }

      if (currentStep >= _fadeSteps) {
        timer.cancel();
        _fadeTimer = null;
      }
    });
  }

  /// Applies [volumePercentage] (0.0 to 1.0) to [AudioManager.STREAM_ALARM].
  static Future<void> _applySystemAlarmVolume(double volumePercentage) async {
    if (!Platform.isAndroid) return;
    try {
      const channel = MethodChannel(_alarmSoundChannel);
      await channel.invokeMethod<void>(
        'setSystemAlarmVolume',
        volumePercentage.clamp(0.0, 1.0),
      );
    } catch (_) {
      // Channel may be absent in headless isolates or tests.
    }
  }
}
