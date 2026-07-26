import 'package:flutter_tts/flutter_tts.dart';

/// Text-to-speech service for the alarm dismissal briefing.
class RA_TtsService {
  RA_TtsService._();

  static FlutterTts? _tts;

  /// Initialises the TTS engine.
  static Future<void> init() async {
    try {
      _tts = FlutterTts();
      await _tts!.setLanguage('en-US');
      await _tts!.setSpeechRate(0.5);
      await _tts!.setVolume(1.0);
      await _tts!.setPitch(1.0);
    } catch (_) {
      // Ignore TTS plugin init errors in headless test environments
    }
  }

  /// Speaks the dismissal briefing for a routine.
  static Future<void> speakDismissalBriefing({
    required String routineName,
    required DateTime nextTriggerTime,
  }) async {
    try {
      if (_tts == null) await init();

      final hour = nextTriggerTime.hour;
      final minute = nextTriggerTime.minute;
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      final minuteStr = minute == 0 ? '' : ' $minute';

      final message =
          '$routineName dismissed. Next alarm at $displayHour$minuteStr $period.';

      await _tts?.speak(message);
    } catch (_) {
      // Ignore TTS speak errors in headless test environments
    }
  }

  /// Stops any ongoing speech.
  static Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {
      // Ignore TTS stop errors in headless test environments
    }
  }

  /// Cleans up the TTS engine.
  static Future<void> dispose() async {
    try {
      await _tts?.stop();
    } catch (_) {
      // Ignore TTS dispose errors in headless test environments
    }
    _tts = null;
  }
}
