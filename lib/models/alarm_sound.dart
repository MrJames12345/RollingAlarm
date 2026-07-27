import 'dart:convert';

import 'package:rolling_alarm/enums/alarm_sound_source.dart';

/// Selected alarm sound persisted in [RoutineModel.AudioUri].
///
/// Uses a small JSON envelope so source, playable URI, and display label travel
/// together. Legacy plain URI strings remain readable.
class RA_AlarmSound {
  final RA_AlarmSoundSource source;
  final String? uri;

  /// Embedded metadata title (ID3 / MediaStore TITLE), or a fallback label.
  final String? label;

  /// Raw OS file name including extension (MediaStore DISPLAY_NAME).
  final String? fileName;

  const RA_AlarmSound({
    required this.source,
    this.uri,
    this.label,
    this.fileName,
  });

  static const RA_AlarmSound silent = RA_AlarmSound(
    source: RA_AlarmSoundSource.silent,
    label: 'Silent',
  );

  static const RA_AlarmSound deviceDefault = RA_AlarmSound(
    source: RA_AlarmSoundSource.deviceDefault,
    label: 'Default',
  );

  /// True when this selection should play no audio.
  bool get isSilent => source == RA_AlarmSoundSource.silent;

  String get displayLabel {
    final named = label?.trim();
    if (named != null && named.isNotEmpty) return named;
    final file = fileName?.trim();
    if (file != null && file.isNotEmpty) return file;
    return source.label;
  }

  /// OS file name for list subtitles when it differs from [displayLabel].
  String? get listFileName {
    final file = fileName?.trim();
    if (file == null || file.isEmpty) return null;
    if (file.toLowerCase() == displayLabel.toLowerCase()) return null;
    return file;
  }

  /// True when [just_audio] can load [uri] directly.
  ///
  /// Device ringtone URIs are excluded; those need native [Ringtone] playback.
  bool get hasPlayableUri {
    final value = uri?.trim() ?? '';
    if (value.isEmpty) return false;
    if (source == RA_AlarmSoundSource.deviceSounds) return false;
    return value.startsWith('content:') ||
        value.startsWith('file:') ||
        value.startsWith('http:') ||
        value.startsWith('https:');
  }

  /// True when this sound should play through Android Ringtone, not just_audio.
  bool get usesNativeRingtone {
    if (source != RA_AlarmSoundSource.deviceSounds) return false;
    final value = uri?.trim() ?? '';
    return value.startsWith('content:') ||
        value.startsWith('file:') ||
        value.startsWith('http:') ||
        value.startsWith('https:');
  }

  String encode() {
    if (source == RA_AlarmSoundSource.deviceDefault &&
        (uri == null || uri!.isEmpty)) {
      return '';
    }
    return jsonEncode({
      'v': 1,
      'source': source.storageKey,
      if (uri != null && uri!.isNotEmpty) 'uri': uri,
      if (label != null && label!.isNotEmpty) 'label': label,
      if (fileName != null && fileName!.isNotEmpty) 'fileName': fileName,
    });
  }

  /// Decodes [raw] from Drift. Empty / null means the bundled default tone.
  static RA_AlarmSound decode(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty || value == 'default_ringtone') {
      return deviceDefault;
    }
    if (value.startsWith('{')) {
      try {
        final map = jsonDecode(value) as Map<String, dynamic>;
        return RA_AlarmSound(
          source: AlarmSoundSourceDetails.fromStorageKey(
            map['source'] as String? ?? 'default',
          ),
          uri: map['uri'] as String?,
          label: map['label'] as String?,
          fileName: map['fileName'] as String?,
        );
      } catch (_) {
        return deviceDefault;
      }
    }
    // Legacy plain URI / path.
    return RA_AlarmSound(
      source: value.startsWith('content:')
          ? RA_AlarmSoundSource.deviceSounds
          : RA_AlarmSoundSource.localFile,
      uri: value,
      label: value.split('/').last,
      fileName: value.split('/').last,
    );
  }
}
