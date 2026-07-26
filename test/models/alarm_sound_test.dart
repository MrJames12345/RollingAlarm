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

    test('round trips device sound json', () {
      const sound = RA_AlarmSound(
        source: RA_AlarmSoundSource.deviceSounds,
        uri: 'content://media/external/audio/media/1',
        label: 'Argon',
      );
      final decoded = RA_AlarmSound.decode(sound.encode());
      expect(decoded.source, RA_AlarmSoundSource.deviceSounds);
      expect(decoded.uri, sound.uri);
      expect(decoded.label, 'Argon');
      expect(decoded.hasPlayableUri, isFalse);
      expect(decoded.usesNativeRingtone, isTrue);
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
