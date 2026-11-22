import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/components/common/app_theme_scope.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/page_scaffold.dart';
import 'package:rolling_alarm/components/common/press_scale.dart';
import 'package:rolling_alarm/components/common/pro_badge.dart';
import 'package:rolling_alarm/components/common/status_message.dart';
import 'package:rolling_alarm/components/field/input_decoration.dart';
import 'package:rolling_alarm/enums/alarm_sound_source.dart';
import 'package:rolling_alarm/enums/app_theme_mode.dart';
import 'package:rolling_alarm/models/alarm_sound.dart';
import 'package:rolling_alarm/pages/paywall.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm_sound_picker.dart';
import 'package:rolling_alarm/services/audio.dart';
import 'package:rolling_alarm/services/sound_preview.dart';
import 'package:rolling_alarm/styles.dart';

/// Alarm sound picker page for selecting Silent, Default, custom local files,
/// or system device sounds.
class AlarmSoundPickerPage extends ConsumerStatefulWidget {
  final RA_AlarmSound initial;

  const AlarmSoundPickerPage({super.key, required this.initial});

  @override
  ConsumerState<AlarmSoundPickerPage> createState() =>
      _AlarmSoundPickerPageState();
}

class _AlarmSoundPickerPageState extends ConsumerState<AlarmSoundPickerPage> {
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
    // Show Silent / Default / spinner immediately; start the system ringtone
    // scan only after the fade transition so the page is not blocked mid-open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startLoadingAfterTransition());
    });
  }

  Future<void> _startLoadingAfterTransition() async {
    await Future<void>.delayed(RA_ShapeStyles.pageFadeDuration);
    if (!mounted) return;
    await _loadDeviceSounds();
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
    final playable = sounds
        .where((sound) {
          final uri = sound.uri?.trim();
          return uri != null && uri.isNotEmpty;
        })
        .toList(growable: false);
    setState(() {
      _deviceSounds = playable;
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

  Future<void> _pickCustomLocalFile() async {
    await RA_SoundPreviewService.stop();
    if (!mounted) return;
    if (!ref.read(IsProProvider)) {
      final unlocked = await PaywallPage.show(
        context,
        featureTrigger: 'Use custom local audio files with Pro',
      );
      if (!unlocked || !mounted) return;
    }
    final picked = await RA_AlarmSoundPickerService.pickLocalFile(
      onError: (message) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: RA_ColourStyles.surface,
            shape: RoundedRectangleBorder(
              borderRadius: RA_ShapeStyles.largeBorderRadius,
              side: BorderSide(color: RA_ShapeStyles.idleSurfaceBorder),
            ),
            content: Text(
              message,
              style: RA_TextStyles.smallFont.copyWith(
                color: RA_ColourStyles.softCoral,
              ),
            ),
          ),
        );
      },
    );
    if (picked != null && mounted) {
      await _preview(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    RA_AppThemeScope.of(context);
    final isPro = ref.watch(IsProProvider);
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
                  foregroundColor: RA_ColourStyles.onAccent,
                  elevation: 0,
                  highlightElevation: 0,
                  splashColor: RA_ColourStyles.mode == AppThemeModeEnum.Light
                      ? RA_ColourStyles.onAccent.withValues(alpha: 0.18)
                      : RA_ColourStyles.primary.withValues(alpha: 0.22),
                  shape: RoundedRectangleBorder(
                    borderRadius: RA_ShapeStyles.largeBorderRadius,
                    side: RA_ColourStyles.mode == AppThemeModeEnum.Light
                        ? BorderSide(
                            color: RA_ColourStyles.onAccent.withValues(
                              alpha: 0.14,
                            ),
                            width: 1,
                          )
                        : BorderSide.none,
                  ),
                  tooltip: _isPlaying ? 'Pause preview' : 'Play preview',
                  onPressed: () {
                    RA_Haptics.heavyUnawaited();
                    unawaited(_togglePreview());
                  },
                  child: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 28,
                    color: RA_ColourStyles.onAccent,
                  ),
                ),
              ),
            )
          : null,
      body: _DeviceSoundsBody(
        loading: _loadingDevice,
        sounds: _deviceSounds,
        selected: _selected,
        isPro: isPro,
        onSelectSilent: () => unawaited(_preview(RA_AlarmSound.silent)),
        onSelectDefault: () => unawaited(_preview(RA_AlarmSound.deviceDefault)),
        onPickCustomFile: () => unawaited(_pickCustomLocalFile()),
        onSelectSound: (sound) => unawaited(_preview(sound)),
      ),
    );
  }
}

class _DeviceSoundsBody extends StatefulWidget {
  final bool loading;
  final List<RA_AlarmSound> sounds;
  final RA_AlarmSound selected;
  final bool isPro;
  final VoidCallback onSelectSilent;
  final VoidCallback onSelectDefault;
  final VoidCallback onPickCustomFile;
  final ValueChanged<RA_AlarmSound> onSelectSound;

  const _DeviceSoundsBody({
    required this.loading,
    required this.sounds,
    required this.selected,
    required this.isPro,
    required this.onSelectSilent,
    required this.onSelectDefault,
    required this.onPickCustomFile,
    required this.onSelectSound,
  });

  @override
  State<_DeviceSoundsBody> createState() => _DeviceSoundsBodyState();
}

class _DeviceSoundsBodyState extends State<_DeviceSoundsBody> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();
  final GlobalKey _searchKey = GlobalKey();
  String _query = '';

  /// FAB glow clearance inside the scrollable list (not empty page padding).
  static const double _fabListClearance =
      RA_ShapeStyles.space48 + RA_ShapeStyles.space48;

  /// Space between tile trailing edge and the scrollbar track.
  static const double _scrollbarGap = RA_ShapeStyles.space8;

  /// Margin between scrollbar and the screen edge.
  static const double _scrollbarEdgeInset = RA_ShapeStyles.space8;

  /// Right inset for content: gap + scrollbar thickness.
  static const double _contentRightInset =
      _scrollbarGap + RA_ShapeStyles.space8;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChanged);
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchFocusChanged() {
    setState(() {});
    if (!_searchFocusNode.hasFocus) return;
    unawaited(_scrollSearchToTop());
  }

  Future<void> _scrollSearchToTop() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final searchContext = _searchKey.currentContext;
    if (searchContext == null || !searchContext.mounted) return;
    await Scrollable.ensureVisible(
      searchContext,
      duration: RA_ShapeStyles.stateTransitionDuration,
      curve: Curves.easeOut,
      alignment: 0,
    );
  }

  List<RA_AlarmSound> get _filteredSounds {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.sounds;
    return widget.sounds
        .where((sound) {
          final title = sound.displayLabel.toLowerCase();
          final file = sound.fileName?.toLowerCase() ?? '';
          return title.contains(query) || file.contains(query);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredSounds;
    final searchFocused = _searchFocusNode.hasFocus;
    // Extra extent so Search can scroll flush with the top of the viewport.
    final searchScrollPad = searchFocused
        ? MediaQuery.sizeOf(context).height * 0.4
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RA_ShapeStyles.space16,
        RA_ShapeStyles.space16,
        _scrollbarEdgeInset,
        0,
      ),
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        trackVisibility: true,
        interactive: true,
        thickness: RA_ShapeStyles.space8,
        radius: const Radius.circular(RA_ShapeStyles.space8),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.only(right: _contentRightInset),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _SoundTile(
                    title: 'Silent',
                    subtitle: 'No audio',
                    selected:
                        widget.selected.source == RA_AlarmSoundSource.silent,
                    onTap: widget.onSelectSilent,
                  ),
                  const SizedBox(height: RA_ShapeStyles.space8),
                  _SoundTile(
                    title: 'Default',
                    subtitle: 'Rolling Alarm tone',
                    selected:
                        widget.selected.source ==
                        RA_AlarmSoundSource.deviceDefault,
                    onTap: widget.onSelectDefault,
                  ),
                  const SizedBox(height: RA_ShapeStyles.space8),
                  _SoundTile(
                    title:
                        widget.selected.source == RA_AlarmSoundSource.localFile
                        ? widget.selected.displayLabel
                        : 'Custom audio file',
                    subtitle:
                        widget.selected.source == RA_AlarmSoundSource.localFile
                        ? (widget.selected.listFileName ??
                              'Local audio file · Tap to change')
                        : 'Choose an audio file from your device',
                    selected:
                        widget.selected.source == RA_AlarmSoundSource.localFile,
                    trailing: !widget.isPro ? const RA_ProBadge() : null,
                    onTap: widget.onPickCustomFile,
                  ),
                  const SizedBox(height: RA_ShapeStyles.space24),
                  Text(
                    'Device sounds',
                    style: RA_TextStyles.tinyFont.copyWith(
                      color: RA_ColourStyles.mutedPrimary,
                    ),
                  ),
                  const SizedBox(height: RA_ShapeStyles.space8),
                ]),
              ),
            ),
            if (widget.loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (widget.sounds.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: EdgeInsets.only(right: _contentRightInset),
                  child: RA_StatusMessage(
                    icon: Icons.music_off,
                    title: 'No device sounds',
                    message: 'No device sounds were found on this phone.',
                  ),
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.only(right: _contentRightInset),
                sliver: SliverToBoxAdapter(
                  child: KeyedSubtree(
                    key: _searchKey,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: RA_ShapeStyles.minTouchTarget,
                      ),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        style: RA_TextStyles.mediumFont,
                        cursorColor: RA_ColourStyles.secondary,
                        textCapitalization: TextCapitalization.none,
                        onChanged: (value) => setState(() => _query = value),
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        decoration: RA_InputDecoration(
                          hintText: 'Search...',
                          hintStyle: RA_TextStyles.mediumFont.copyWith(
                            color: RA_ColourStyles.faintPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: RA_ShapeStyles.space8),
              ),
              if (filtered.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.only(right: _contentRightInset),
                    child: RA_StatusMessage(
                      icon: Icons.search_off,
                      title: 'No matches',
                      message: 'No device sounds match your search.',
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.only(
                    right: _contentRightInset,
                    bottom: _fabListClearance + searchScrollPad,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final sound = filtered[index];
                      return Padding(
                        padding: const EdgeInsets.only(
                          bottom: RA_ShapeStyles.space8,
                        ),
                        child: _SoundTile(
                          title: sound.displayLabel,
                          subtitle: sound.listFileName,
                          selected:
                              widget.selected.source ==
                                  RA_AlarmSoundSource.deviceSounds &&
                              widget.selected.uri == sound.uri,
                          onTap: () => widget.onSelectSound(sound),
                        ),
                      );
                    }, childCount: filtered.length),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SoundTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool selected;
  final Widget? trailing;
  final VoidCallback onTap;

  const _SoundTile({
    required this.title,
    this.subtitle,
    required this.selected,
    this.trailing,
    required this.onTap,
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
                  ? Color.alphaBlend(
                      RA_ColourStyles.secondary.withValues(alpha: 0.08),
                      RA_ColourStyles.surface,
                    )
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: RA_TextStyles.smallFont.copyWith(
                            color: selected
                                ? RA_ColourStyles.secondary
                                : RA_ColourStyles.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: RA_ShapeStyles.space8),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: RA_TextStyles.tinyFont.copyWith(
                              color: RA_ColourStyles.secondary,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: RA_ShapeStyles.space8),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
