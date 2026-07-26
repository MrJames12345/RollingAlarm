/// Alarm sound sources.
enum RA_AlarmSoundSource {
  /// No audio; vibration (if enabled) still runs.
  silent,

  /// Bundled Rolling Alarm tone.
  deviceDefault,

  /// System alarm / ringtone sounds on the device.
  deviceSounds,

  /// Audio file from device storage.
  localFile,
}

/// Helpers for [RA_AlarmSoundSource] labels and Android packages.
extension AlarmSoundSourceDetails on RA_AlarmSoundSource {
  String get label => switch (this) {
    RA_AlarmSoundSource.silent => 'Silent',
    RA_AlarmSoundSource.deviceDefault => 'Default',
    RA_AlarmSoundSource.deviceSounds => 'Device sounds',
    RA_AlarmSoundSource.localFile => 'Local file',
  };

  /// Android package name for install checks / store links, if any.
  String? get androidPackage => null;

  bool get isStreamingApp => false;

  String get storageKey => switch (this) {
    RA_AlarmSoundSource.silent => 'silent',
    RA_AlarmSoundSource.deviceDefault => 'default',
    RA_AlarmSoundSource.deviceSounds => 'device',
    RA_AlarmSoundSource.localFile => 'local',
  };

  static RA_AlarmSoundSource fromStorageKey(String key) => switch (key) {
    'silent' => RA_AlarmSoundSource.silent,
    'device' => RA_AlarmSoundSource.deviceSounds,
    'local' => RA_AlarmSoundSource.localFile,
    _ => RA_AlarmSoundSource.deviceDefault,
  };
}

