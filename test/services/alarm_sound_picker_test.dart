import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_alarm/enums/alarm_sound_source.dart';
import 'package:rolling_alarm/services/alarm_sound_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.rolling_alarm/alarm_sound');

  group('RA_AlarmSoundPickerService', () {
    test('isValidAudioFile accepts recognized audio formats', () {
      expect(RA_AlarmSoundPickerService.isValidAudioFile('song.mp3'), isTrue);
      expect(RA_AlarmSoundPickerService.isValidAudioFile('/music/alarm.wav'), isTrue);
      expect(RA_AlarmSoundPickerService.isValidAudioFile('content://media/external/audio/1'), isTrue);
      expect(RA_AlarmSoundPickerService.isValidAudioFile('tone.FLAC'), isTrue);
    });

    test('isValidAudioFile rejects non-audio file formats', () {
      expect(RA_AlarmSoundPickerService.isValidAudioFile('document.pdf'), isFalse);
      expect(RA_AlarmSoundPickerService.isValidAudioFile('image.png'), isFalse);
      expect(RA_AlarmSoundPickerService.isValidAudioFile('video.mp4'), isFalse);
      expect(RA_AlarmSoundPickerService.isValidAudioFile('archive.zip'), isFalse);
      expect(RA_AlarmSoundPickerService.isValidAudioFile(''), isFalse);
      expect(RA_AlarmSoundPickerService.isValidAudioFile(null), isFalse);
    });

    test('pickLocalFile invokes native pickLocalFile channel and returns sound', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'pickLocalFile') {
          return {
            'uri': 'content://media/external/file/100',
            'title': 'Morning Melody.mp3',
          };
        }
        return null;
      });

      String? errorMessage;
      final sound = await RA_AlarmSoundPickerService.pickLocalFile(
        onError: (msg) => errorMessage = msg,
      );

      expect(sound, isNotNull);
      expect(sound!.source, RA_AlarmSoundSource.localFile);
      expect(sound.uri, 'content://media/external/file/100');
      expect(sound.label, 'Morning Melody.mp3');
      expect(errorMessage, isNull);
    });

    test('pickLocalFile rejects non-audio file from channel and triggers onError', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'pickLocalFile') {
          return {
            'uri': 'content://media/external/file/101',
            'title': 'Resume.pdf',
          };
        }
        return null;
      });

      String? errorMessage;
      final sound = await RA_AlarmSoundPickerService.pickLocalFile(
        onError: (msg) => errorMessage = msg,
      );

      expect(sound, isNull);
      expect(errorMessage, contains('not an audio file'));
      expect(errorMessage, contains('Resume.pdf'));
    });

    test('pickLocalFile handles PlatformException non_audio_file from native side', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'pickLocalFile') {
          throw PlatformException(
            code: 'non_audio_file',
            message: 'The selected file is not an audio file. Please choose a valid audio format.',
          );
        }
        return null;
      });

      String? errorMessage;
      final sound = await RA_AlarmSoundPickerService.pickLocalFile(
        onError: (msg) => errorMessage = msg,
      );

      expect(sound, isNull);
      expect(errorMessage, contains('not an audio file'));
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  });
}
