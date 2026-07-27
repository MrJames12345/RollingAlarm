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
  static bool _nativePlaying = false;

  /// Last sound started via [play], used to resume after a native pause.
  static RA_AlarmSound? _currentSound;

  static const String _defaultAsset = 'assets/audio/default_alarm.mp3';

  /// Whether preview audio is currently playing.
  static bool get isPlaying {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return _testPlaying;
    }
    if (_usingNativeRingtone) return _nativePlaying;
    return _player?.playing ?? false;
  }

  /// Emits whenever preview play/pause state changes.
  static Stream<bool> get playingStream => _playingController.stream;

  /// Starts (or restarts) preview for [sound] at full volume, looping.
  static Future<void> play(RA_AlarmSound sound) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _testPlaying = true;
      _currentSound = sound;
      _playingController.add(true);
      return;
    }

    try {
      await stop(clearCurrent: false);
      _currentSound = sound;

      if (sound.isSilent) {
        _emitPlaying(false);
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
          _nativePlaying = true;
          _emitPlaying(true);
          return;
        }
        await stop();
        return;
      }

      await _configureSession();

      final player = AudioPlayer();
      _player = player;
      _playingSub = player.playingStream.listen((playing) {
        _emitPlaying(playing);
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
      _playingController.add(_testPlaying);
      return;
    }

    if (_usingNativeRingtone ||
        (_currentSound != null && _currentSound!.usesNativeRingtone)) {
      if (_nativePlaying) {
        await RA_DeviceRingtone.stop();
        _usingNativeRingtone = false;
        _nativePlaying = false;
        _emitPlaying(false);
        return;
      }

      final sound = _currentSound;
      if (sound == null || sound.isSilent || !sound.usesNativeRingtone) {
        return;
      }
      await play(sound);
      return;
    }

    final player = _player;
    if (player == null) {
      final sound = _currentSound;
      if (sound != null && !sound.isSilent) {
        await play(sound);
      }
      return;
    }

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
  ///
  /// When [clearCurrent] is false, keeps [_currentSound] so [togglePause] can
  /// resume the same selection after a restart inside [play].
  static Future<void> stop({bool clearCurrent = true}) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _testPlaying = false;
      if (clearCurrent) _currentSound = null;
      if (!_playingController.isClosed) {
        _playingController.add(false);
      }
      return;
    }

    await _playingSub?.cancel();
    _playingSub = null;

    if (_usingNativeRingtone || _nativePlaying) {
      _usingNativeRingtone = false;
      _nativePlaying = false;
      await RA_DeviceRingtone.stop();
    }

    try {
      await _player?.stop();
      await _player?.dispose();
    } catch (_) {
      // Ignore stop/dispose errors.
    }
    _player = null;

    if (clearCurrent) {
      _currentSound = null;
    }

    _emitPlaying(false);
  }

  static void _emitPlaying(bool playing) {
    if (!_playingController.isClosed) {
      _playingController.add(playing);
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
