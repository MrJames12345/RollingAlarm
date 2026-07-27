import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_alarm/enums/alarm_sound_source.dart';
import 'package:rolling_alarm/models/alarm_sound.dart';

void main() {
  group('RA_AlarmSound', () {
    test('default encodes to empty and decodes from null', () {
      expect(RA_AlarmSound.deviceDefault.encode(), isEmpty);
      expect(
        RA_AlarmSound.decode(null).source,
        RA_AlarmSoundSource.deviceDefault,
      );
      expect(
        RA_AlarmSound.decode('').source,
        RA_AlarmSoundSource.deviceDefault,
      );
    });

    test('silent round trips and skips playable audio', () {
      final encoded = RA_AlarmSound.silent.encode();
      expect(encoded, isNotEmpty);
      final decoded = RA_AlarmSound.decode(encoded);
      expect(decoded.source, RA_AlarmSoundSource.silent);
      expect(decoded.isSilent, isTrue);
      expect(decoded.hasPlayableUri, isFalse);
      expect(decoded.usesNativeRingtone, isFalse);
      expect(decoded.displayLabel, 'Silent');
    });

    test('round trips device sound json', () {
      const sound = RA_AlarmSound(
        source: RA_AlarmSoundSource.deviceSounds,
        uri: 'content://media/external/audio/media/1',
        label: 'Argon',
        fileName: 'argon_tone.ogg',
      );
      final decoded = RA_AlarmSound.decode(sound.encode());
      expect(decoded.source, RA_AlarmSoundSource.deviceSounds);
      expect(decoded.uri, sound.uri);
      expect(decoded.label, 'Argon');
      expect(decoded.fileName, 'argon_tone.ogg');
      expect(decoded.listFileName, 'argon_tone.ogg');
      expect(decoded.hasPlayableUri, isFalse);
      expect(decoded.usesNativeRingtone, isTrue);
    });

    test('listFileName is omitted when it matches the metadata title', () {
      const sound = RA_AlarmSound(
        source: RA_AlarmSoundSource.deviceSounds,
        uri: 'content://media/external/audio/media/2',
        label: 'wake.mp3',
        fileName: 'wake.mp3',
      );
      expect(sound.displayLabel, 'wake.mp3');
      expect(sound.listFileName, isNull);
    });

    test('displayLabel falls back to fileName then source label', () {
      const withFile = RA_AlarmSound(
        source: RA_AlarmSoundSource.deviceSounds,
        uri: 'content://media/external/audio/media/3',
        fileName: 'track.mp3',
      );
      expect(withFile.displayLabel, 'track.mp3');

      const bare = RA_AlarmSound(source: RA_AlarmSoundSource.deviceSounds);
      expect(bare.displayLabel, RA_AlarmSoundSource.deviceSounds.label);
    });

    test('reads legacy plain file uri', () {
      final decoded = RA_AlarmSound.decode('file:///music/wake.mp3');
      expect(decoded.source, RA_AlarmSoundSource.localFile);
      expect(decoded.uri, 'file:///music/wake.mp3');
      expect(decoded.hasPlayableUri, isTrue);
      expect(decoded.usesNativeRingtone, isFalse);
    });

    test('legacy content uri uses native ringtone', () {
      final decoded = RA_AlarmSound.decode(
        'content://media/internal/audio/media/27',
      );
      expect(decoded.source, RA_AlarmSoundSource.deviceSounds);
      expect(decoded.usesNativeRingtone, isTrue);
      expect(decoded.hasPlayableUri, isFalse);
    });
  });
}
