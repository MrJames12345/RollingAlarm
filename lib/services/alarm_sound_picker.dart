import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:rolling_alarm/enums/alarm_sound_source.dart';
import 'package:rolling_alarm/models/alarm_sound.dart';

/// Platform helpers for device sounds and local audio file selection.
class RA_AlarmSoundPickerService {
  RA_AlarmSoundPickerService._();

  static const MethodChannel _channel = MethodChannel(
    'com.example.rolling_alarm/alarm_sound',
  );

  /// Alarm and ringtone entries from [RingtoneManager].
  static Future<List<RA_AlarmSound>> listDeviceSounds() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'listDeviceSounds',
      );
      if (raw == null) return const [];
      return raw.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return RA_AlarmSound(
          source: RA_AlarmSoundSource.deviceSounds,
          uri: map['uri'] as String?,
          label: map['title'] as String? ?? 'Device sound',
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Opens the system ringtone picker (alarm type).
  static Future<RA_AlarmSound?> pickDeviceSound({String? existingUri}) async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'pickDeviceSound',
        {'existingUri': existingUri},
      );
      if (raw == null) return null;
      final map = Map<String, dynamic>.from(raw);
      final uri = map['uri'] as String?;
      if (uri == null || uri.isEmpty) return null;
      return RA_AlarmSound(
        source: RA_AlarmSoundSource.deviceSounds,
        uri: uri,
        label: map['title'] as String? ?? 'Device sound',
      );
    } catch (_) {
      return null;
    }
  }

  /// Picks an audio file from device storage.
  ///
  /// Returns `null` when the user cancels without selecting a file.
  static Future<RA_AlarmSound?> pickLocalFile({
    void Function(String message)? onError,
  }) async {
    try {
      final native = await _pickLocalFileNative(onError: onError);
      if (native.handled) return native.sound;
      return _pickLocalFileFallback(onError: onError);
    } catch (e) {
      onError?.call('Failed to select file: $e');
      return null;
    }
  }

  /// Native Android channel result. [handled] is true when the channel replied
  /// (including cancel / validation errors), so FilePicker must not open.
  static Future<({bool handled, RA_AlarmSound? sound})> _pickLocalFileNative({
    void Function(String message)? onError,
  }) async {
    try {
      // Use dynamic so a null cancel reply never type-casts as a non-null Map.
      final raw = await _channel.invokeMethod<dynamic>('pickLocalFile');
      if (raw == null) return (handled: true, sound: null);
      if (raw is! Map) return (handled: true, sound: null);

      final map = Map<String, dynamic>.from(raw);
      final uri = map['uri'] as String?;
      if (uri == null || uri.isEmpty) return (handled: true, sound: null);
      final label = map['title'] as String? ?? 'Local file';

      if (!_isAcceptableAudioLabel(label, uri)) {
        onError?.call(
          'Selected file is not an audio file ($label). Please choose a valid audio format (e.g. MP3, WAV, OGG, M4A, FLAC).',
        );
        return (handled: true, sound: null);
      }

      return (
        handled: true,
        sound: RA_AlarmSound(
          source: RA_AlarmSoundSource.localFile,
          uri: uri,
          label: label,
        ),
      );
    } on PlatformException catch (e) {
      if (e.code == 'non_audio_file' || e.code == 'not_audio') {
        onError?.call(
          e.message ??
              'Selected file is not an audio file. Please choose a valid audio format.',
        );
        return (handled: true, sound: null);
      }
      if (e.code == 'notImplemented') {
        return (handled: false, sound: null);
      }
      onError?.call('Failed to select file: ${e.message ?? e.code}');
      return (handled: true, sound: null);
    } on MissingPluginException {
      return (handled: false, sound: null);
    }
  }

  static Future<RA_AlarmSound?> _pickLocalFileFallback({
    void Function(String message)? onError,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'mp3', 'wav', 'ogg', 'm4a', 'flac', 'aac',
        'wma', 'opus', 'amr', 'mid', 'midi', 'aiff',
      ],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;

    final name = file.name;
    final path = file.path;
    final identifier = file.identifier;
    final rawUri = (path != null && path.isNotEmpty) ? path : identifier;
    if (rawUri == null || rawUri.isEmpty) return null;

    if (!isValidAudioFile(name) && !isValidAudioFile(rawUri)) {
      onError?.call(
        'Selected file is not an audio file ($name). Please choose a valid audio format (e.g. MP3, WAV, OGG, M4A, FLAC).',
      );
      return null;
    }

    final uri = (rawUri.startsWith('content:') ||
            rawUri.startsWith('file:') ||
            rawUri.startsWith('http:') ||
            rawUri.startsWith('https:'))
        ? rawUri
        : Uri.file(rawUri).toString();

    return RA_AlarmSound(
      source: RA_AlarmSoundSource.localFile,
      uri: uri,
      label: name.isNotEmpty ? name : 'Local file',
    );
  }

  static bool _isAcceptableAudioLabel(String label, String uri) {
    const nonAudioExtensions = {
      '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.pdf', '.doc', '.docx',
      '.xls', '.xlsx', '.ppt', '.pptx', '.txt', '.rtf', '.csv', '.zip', '.rar',
      '.7z', '.tar', '.gz', '.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv',
      '.webm', '.exe', '.apk', '.bin', '.iso', '.xml', '.html', '.json',
    };
    final lowerLabel = label.trim().toLowerCase();
    final lowerUri = uri.trim().toLowerCase();
    for (final ext in nonAudioExtensions) {
      if (lowerLabel.endsWith(ext) || lowerUri.split('?').first.endsWith(ext)) {
        return false;
      }
    }
    return true;
  }

  /// Validates whether a file path or name has a recognized audio extension.
  static bool isValidAudioFile(String? pathOrName) {
    if (pathOrName == null || pathOrName.trim().isEmpty) return false;
    if (pathOrName.startsWith('content:') && !pathOrName.contains('.')) {
      return true;
    }
    final clean = pathOrName.trim().toLowerCase();
    const audioExtensions = [
      '.mp3', '.wav', '.ogg', '.m4a', '.flac', '.aac',
      '.wma', '.opus', '.amr', '.mid', '.midi', '.aiff',
    ];
    return audioExtensions.any((ext) => clean.endsWith(ext));
  }
}

