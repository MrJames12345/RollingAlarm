import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rolling_alarm/models/alarm_sound.dart';
import 'package:rolling_alarm/services/device_ringtone.dart';

/// Lightweight preview playback for the alarm sound picker.
///
/// Separate from alarm ringing so preview never uses fade-in, isolate stop
/// ports, or alarm stream usage.
class RA_SoundPreviewService {
  RA_SoundPreviewService._();

  static AudioPlayer? _player;
  static StreamSubscription<bool>? _playingSub;
  static final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  static bool _testPlaying = false;
  static bool _usingNativeRingtone = false;

  static const String _defaultAsset = 'assets/audio/default_alarm.wav';

  /// Whether preview audio is currently playing.
  static bool get isPlaying {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return _testPlaying;
    }
    if (_usingNativeRingtone) return true;
    return _player?.playing ?? false;
  }

  /// Emits whenever preview play/pause state changes.
  static Stream<bool> get playingStream => _playingController.stream;

  /// Starts (or restarts) preview for [sound] at full volume, looping.
  static Future<void> play(RA_AlarmSound sound) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _testPlaying = true;
      _playingController.add(true);
      return;
    }

    try {
      await stop();

      if (sound.isSilent) {
        return;
      }

      if (sound.usesNativeRingtone) {
        final started = await RA_DeviceRingtone.play(
          uri: sound.uri!.trim(),
          loop: true,
          asAlarm: false,
          fadeInMs: 0,
        );
        if (started == true) {
          _usingNativeRingtone = true;
          if (!_playingController.isClosed) {
            _playingController.add(true);
          }
          return;
        }
        await stop();
        return;
      }

      await _configureSession();

      final player = AudioPlayer();
      _player = player;
      _playingSub = player.playingStream.listen((playing) {
        if (!_playingController.isClosed) {
          _playingController.add(playing);
        }
      });

      if (sound.hasPlayableUri) {
        await player.setUrl(sound.uri!);
      } else {
        await player.setAsset(_defaultAsset);
      }
      await player.setLoopMode(LoopMode.one);
      await player.setVolume(1.0);
      await player.play();
    } catch (_) {
      await stop();
    }
  }

  /// Toggles pause / resume for the current preview.
  static Future<void> togglePause() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _testPlaying = !_testPlaying;
      if (!_playingController.isClosed) {
        _playingController.add(_testPlaying);
      }
      return;
    }

    if (_usingNativeRingtone) {
      if (isPlaying) {
        await RA_DeviceRingtone.stop();
        _usingNativeRingtone = false;
        if (!_playingController.isClosed) {
          _playingController.add(false);
        }
      }
      return;
    }

    final player = _player;
    if (player == null) return;

    try {
      if (player.playing) {
        await player.pause();
      } else {
        await player.play();
      }
    } catch (_) {
      // Ignore transient player errors during toggle.
    }
  }

  /// Stops preview and disposes the player.
  static Future<void> stop() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _testPlaying = false;
      if (!_playingController.isClosed) {
        _playingController.add(false);
      }
      return;
    }

    await _playingSub?.cancel();
    _playingSub = null;

    if (_usingNativeRingtone) {
      _usingNativeRingtone = false;
      await RA_DeviceRingtone.stop();
    }

    try {
      await _player?.stop();
      await _player?.dispose();
    } catch (_) {
      // Ignore stop/dispose errors.
    }
    _player = null;

    if (!_playingController.isClosed) {
      _playingController.add(false);
    }
  }

  static Future<void> _configureSession() async {
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransient,
        androidWillPauseWhenDucked: true,
      ),
    );
  }
}
