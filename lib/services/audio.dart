import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rolling_alarm/models/alarm_sound.dart';
import 'package:rolling_alarm/services/sound_preview.dart';

/// Manages alarm audio playback with gradual volume fade-in
/// on the alarm audio stream.
class RA_AudioService {
  RA_AudioService._();

  static AudioPlayer? _player;
  static Timer? _fadeTimer;
  static ReceivePort? _controlPort;
  static StreamSubscription<dynamic>? _controlSub;

  static const String _audioPortName = 'ra_audio_control_port';

  /// Bundled fallback tone when a routine has no custom playable URI.
  static const String defaultAlarmAsset = 'assets/audio/default_alarm.wav';

  /// Duration over which the alarm volume fades from 0 to 1.
  static const Duration fadeDuration = Duration(seconds: 10);
  static const int _fadeSteps = 20;

  /// Starts playing the alarm sound with a gradual volume ramp.
  ///
  /// [audioUri] may be a legacy plain URI or an encoded [RA_AlarmSound].
  static Future<void> startAlarm({String? audioUri}) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }

    final existingPort = IsolateNameServer.lookupPortByName(_audioPortName);
    if (existingPort != null && _controlPort == null) {
      return;
    }

    try {
      await RA_SoundPreviewService.stop();
      await stopAlarm();
      _registerControlPort();
      await _configureSession();

      final sound = RA_AlarmSound.decode(audioUri);

      _player = AudioPlayer();
      if (sound.hasPlayableUri) {
        await _player!.setUrl(sound.uri!);
      } else {
        await _player!.setAsset(defaultAlarmAsset);
      }
      await _player!.setLoopMode(LoopMode.one);
      await _player!.setVolume(0.0);
      await _player!.play();

      _startFadeIn();
    } catch (_) {
      // Primary source failed; try bundled default so the visual alarm still
      // has audio when possible.
      try {
        _player ??= AudioPlayer();
        await _player!.setAsset(defaultAlarmAsset);
        await _player!.setLoopMode(LoopMode.one);
        await _player!.setVolume(1.0);
        await _player!.play();
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

  /// Configures the audio session for alarm playback.
  static Future<void> _configureSession() async {
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.alarm,
        ),
        androidAudioFocusGainType:
            AndroidAudioFocusGainType.gainTransientExclusive,
        androidWillPauseWhenDucked: false,
      ),
    );
  }

  /// Gradually increases volume from 0 to 1 over [fadeDuration].
  static void _startFadeIn() {
    final stepDuration = fadeDuration ~/ _fadeSteps;
    int currentStep = 0;

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
}
