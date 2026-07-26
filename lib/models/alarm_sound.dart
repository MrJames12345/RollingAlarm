import 'dart:convert';

import 'package:rolling_alarm/enums/alarm_sound_source.dart';

/// Selected alarm sound persisted in [RoutineModel.AudioUri].
///
/// Uses a small JSON envelope so source, playable URI, and display label travel
/// together. Legacy plain URI strings remain readable.
class RA_AlarmSound {
  final RA_AlarmSoundSource source;
  final String? uri;
  final String? label;

  const RA_AlarmSound({
    required this.source,
    this.uri,
    this.label,
  });

  static const RA_AlarmSound deviceDefault = RA_AlarmSound(
    source: RA_AlarmSoundSource.deviceDefault,
    label: 'Default',
  );

  String get displayLabel {
    final named = label?.trim();
    if (named != null && named.isNotEmpty) return named;
    return source.label;
  }

  /// True when [just_audio] can load [uri] directly.
  bool get hasPlayableUri {
    final value = uri?.trim() ?? '';
    if (value.isEmpty) return false;
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
    );
  }
}
