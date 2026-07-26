import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/page_scaffold.dart';
import 'package:rolling_alarm/components/common/press_scale.dart';
import 'package:rolling_alarm/components/common/status_message.dart';
import 'package:rolling_alarm/enums/alarm_sound_source.dart';
import 'package:rolling_alarm/models/alarm_sound.dart';
import 'package:rolling_alarm/services/alarm_sound_picker.dart';
import 'package:rolling_alarm/services/audio.dart';
import 'package:rolling_alarm/services/sound_preview.dart';
import 'package:rolling_alarm/styles.dart';

/// Alarm sound picker page for selecting device sounds and local audio files.
class AlarmSoundPickerPage extends StatefulWidget {
  final RA_AlarmSound initial;

  const AlarmSoundPickerPage({super.key, required this.initial});

  @override
  State<AlarmSoundPickerPage> createState() => _AlarmSoundPickerPageState();
}

class _AlarmSoundPickerPageState extends State<AlarmSoundPickerPage> {
  List<RA_AlarmSound> _deviceSounds = const [];
  bool _loadingDevice = true;
  late RA_AlarmSound _selected;
  bool _isPlaying = false;
  bool _previewReady = false;
  StreamSubscription<bool>? _playingSub;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    _playingSub = RA_SoundPreviewService.playingStream.listen((playing) {
      if (!mounted) return;
      setState(() => _isPlaying = playing);
    });
    unawaited(_loadDeviceSounds());
  }

  @override
  void dispose() {
    unawaited(_playingSub?.cancel());
    unawaited(RA_SoundPreviewService.stop());
    super.dispose();
  }

  Future<void> _loadDeviceSounds() async {
    final sounds = await RA_AlarmSoundPickerService.listDeviceSounds();
    if (!mounted) return;
    setState(() {
      _deviceSounds = sounds;
      _loadingDevice = false;
    });
  }

  Future<void> _preview(RA_AlarmSound sound) async {
    setState(() {
      _selected = sound;
      _previewReady = !sound.isSilent;
    });
    await RA_AudioService.stopAlarm();
    await RA_SoundPreviewService.play(sound);
  }

  Future<void> _pickLocalFile() async {
    try {
      // Stop preview while the system picker is open so audio session and
      // activity pause do not race with just_audio on cancel.
      await RA_SoundPreviewService.stop();
      if (!mounted) return;

      final picked = await RA_AlarmSoundPickerService.pickLocalFile(
        onError: (message) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                message,
                style: RA_TextStyles.tinyFont.copyWith(
                  color: RA_ColourStyles.surface,
                ),
              ),
              backgroundColor: RA_ColourStyles.softCoral,
            ),
          );
        },
      );
      if (!mounted) return;
      if (picked != null) {
        await _preview(picked);
      }
    } catch (_) {
      // Cancel and picker teardown must never surface as an unhandled crash.
    }
  }

  Future<void> _save() async {
    await RA_SoundPreviewService.stop();
    if (!mounted) return;
    Navigator.pop(context, _selected);
  }

  Future<void> _close() async {
    await RA_SoundPreviewService.stop();
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _togglePreview() async {
    await RA_SoundPreviewService.togglePause();
  }

  @override
  Widget build(BuildContext context) {
    return RA_PageScaffold(
      title: 'Alarm sound',
      leading: RA_AppBarIconButton(
        icon: Icons.close,
        tooltip: 'Close',
        onPressed: () => unawaited(_close()),
      ),
      actions: [
        RA_DialogButton(
          'Save',
          () => unawaited(_save()),
          color: RA_ColourStyles.secondary,
          style: RA_TextStyles.mediumFont,
        ),
      ],
      floatingActionButton: _previewReady
          ? RA_PressScale(
              pressedScale: 0.94,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: RA_ShapeStyles.largeBorderRadius,
                  boxShadow: RA_ShapeStyles.tealGlow,
                ),
                child: FloatingActionButton(
                  backgroundColor: RA_ColourStyles.secondary,
                  foregroundColor: RA_ColourStyles.offBlack,
                  elevation: 0,
                  highlightElevation: 0,
                  splashColor: RA_ColourStyles.primary.withValues(alpha: 0.22),
                  tooltip: _isPlaying ? 'Pause preview' : 'Play preview',
                  onPressed: () {
                    RA_Haptics.heavyUnawaited();
                    unawaited(_togglePreview());
                  },
                  child: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 28,
                  ),
                ),
              ),
            )
          : null,
      body: _DeviceSoundsBody(
        loading: _loadingDevice,
        sounds: _deviceSounds,
        selected: _selected,
        onSelectSilent: () => unawaited(_preview(RA_AlarmSound.silent)),
        onSelectDefault: () => unawaited(_preview(RA_AlarmSound.deviceDefault)),
        onSelectSound: (sound) => unawaited(_preview(sound)),
        onPickLocal: () => unawaited(_pickLocalFile()),
      ),
    );
  }
}

class _DeviceSoundsBody extends StatelessWidget {
  final bool loading;
  final List<RA_AlarmSound> sounds;
  final RA_AlarmSound selected;
  final VoidCallback onSelectSilent;
  final VoidCallback onSelectDefault;
  final ValueChanged<RA_AlarmSound> onSelectSound;
  final VoidCallback onPickLocal;

  const _DeviceSoundsBody({
    required this.loading,
    required this.sounds,
    required this.selected,
    required this.onSelectSilent,
    required this.onSelectDefault,
    required this.onSelectSound,
    required this.onPickLocal,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: RA_ShapeStyles.bodyPaddingWithFab,
      children: [
        _SoundTile(
          title: 'Silent',
          subtitle: 'No audio',
          selected: selected.source == RA_AlarmSoundSource.silent,
          onTap: onSelectSilent,
        ),
        const SizedBox(height: RA_ShapeStyles.space8),
        _SoundTile(
          title: 'Default',
          subtitle: 'Rolling Alarm tone',
          selected: selected.source == RA_AlarmSoundSource.deviceDefault,
          onTap: onSelectDefault,
        ),
        const SizedBox(height: RA_ShapeStyles.space8),
        _SoundTile(
          title: 'Local file',
          subtitle: selected.source == RA_AlarmSoundSource.localFile
              ? selected.displayLabel
              : 'Pick audio from this device',
          selected: selected.source == RA_AlarmSoundSource.localFile,
          onTap: onPickLocal,
          trailing: Icons.folder_open,
        ),
        const SizedBox(height: RA_ShapeStyles.space24),
        Text('Device sounds', style: RA_TextStyles.tinyFont.copyWith(
          color: RA_ColourStyles.mutedPrimary,
        )),
        const SizedBox(height: RA_ShapeStyles.space8),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: RA_ShapeStyles.space24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (sounds.isEmpty)
          const RA_StatusMessage(
            icon: Icons.music_off,
            title: 'No device sounds',
            message: 'No device sounds were found on this phone.',
          )
        else
          ...sounds.map(
            (sound) => Padding(
              padding: const EdgeInsets.only(bottom: RA_ShapeStyles.space8),
              child: _SoundTile(
                title: sound.displayLabel,
                selected:
                    selected.source == RA_AlarmSoundSource.deviceSounds &&
                    selected.uri == sound.uri,
                onTap: () => onSelectSound(sound),
              ),
            ),
          ),
      ],
    );
  }
}

class _SoundTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final IconData? trailing;

  const _SoundTile({
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return RA_PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            RA_Haptics.heavyUnawaited();
            onTap();
          },
          borderRadius: RA_ShapeStyles.largeBorderRadius,
          splashColor: RA_ColourStyles.secondary.withValues(alpha: 0.16),
          highlightColor: RA_ColourStyles.secondary.withValues(alpha: 0.08),
          child: Ink(
            decoration: RA_ShapeStyles.elevatedSurface(
              borderColor: selected
                  ? RA_ColourStyles.secondary.withValues(alpha: 0.35)
                  : null,
              borderWidth: selected ? 1.5 : 1,
              fill: selected
                  ? RA_ColourStyles.secondary.withValues(alpha: 0.08)
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.all(RA_ShapeStyles.space16),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected
                        ? RA_ColourStyles.secondary
                        : RA_ColourStyles.mutedPrimary,
                  ),
                  const SizedBox(width: RA_ShapeStyles.space16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: RA_TextStyles.smallFont.copyWith(
                            color: selected
                                ? RA_ColourStyles.secondary
                                : RA_ColourStyles.primary,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: RA_ShapeStyles.space8),
                          Text(
                            subtitle!,
                            style: RA_TextStyles.tinyFont.copyWith(
                              color: RA_ColourStyles.mutedPrimary,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null)
                    Icon(trailing, color: RA_ColourStyles.mutedPrimary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
