import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/components/common/fitted_text.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/press_scale.dart';
import 'package:rolling_alarm/enums/alarm_action_type_code.dart';
import 'package:rolling_alarm/enums/alarm_side_button_action.dart';
import 'package:rolling_alarm/enums/alarm_snooze_dismiss_layout.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/audio.dart';
import 'package:rolling_alarm/services/notification.dart';
import 'package:rolling_alarm/services/settings.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:rolling_alarm/utils.dart';

class AlarmRingPage extends ConsumerStatefulWidget {
  final int routineId;
  final String routineName;
  final String? audioUri;
  final bool vibrate;
  final int volume;
  final bool fadeIn;

  /// When true, snooze/dismiss only stop audio and pop; no alarm side effects.
  final bool isPreview;

  const AlarmRingPage({
    super.key,
    required this.routineId,
    required this.routineName,
    this.audioUri,
    this.vibrate = true,
    this.volume = 100,
    this.fadeIn = false,
    this.isPreview = false,
  });

  @override
  ConsumerState<AlarmRingPage> createState() => _AlarmRingPageState();
}

class _AlarmRingPageState extends ConsumerState<AlarmRingPage>
    with SingleTickerProviderStateMixin {
  static const MethodChannel _alarmSoundChannel = MethodChannel(
    'com.example.rolling_alarm/alarm_sound',
  );

  late final AnimationController _pulseController;
  late final Animation<double> _pulse;
  late final ValueNotifier<double> _escalation;
  Timer? _escalationTimer;

  /// Applied at the next pulse turnaround so mid-cycle duration changes never
  /// restart the controller (which caused a visible jump).
  Duration _pulseDuration = const Duration(milliseconds: 780);

  /// 0.0 at open, climbs toward 1.0 so the coral pulse grows more aggressive.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    RA_Haptics.heavyUnawaited();
    _escalation = ValueNotifier(0);
    _pulseController = AnimationController(
      vsync: this,
      duration: _pulseDuration,
    );
    // easeInOut on both legs keeps velocity at 0 at the peaks so reverse is
    // seamless. Ping-pong via status listener instead of repeat() so escalation
    // can retarget duration only between half-cycles.
    _pulse = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
      reverseCurve: Curves.easeInOut,
    );
    _pulseController.addStatusListener(_onPulseStatus);
    unawaited(_pulseController.forward());
    _escalationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || _escalation.value >= 1) {
        if (_escalation.value >= 1) _escalationTimer?.cancel();
        return;
      }
      final next = (_escalation.value + 0.08).clamp(0.0, 1.0);
      _escalation.value = next;
      // Quicken the pulse as urgency climbs; duration takes effect on the next
      // half-cycle so the in-flight scale never snaps.
      final ms = (780 - (280 * next)).round();
      _pulseDuration = Duration(milliseconds: ms);
    });
    _alarmSoundChannel.setMethodCallHandler(_onPlatformCall);
    unawaited(_startAlarmAudio());
    unawaited(_syncSideButtonActions());
  }

  void _onPulseStatus(AnimationStatus status) {
    if (!mounted) return;
    _pulseController.duration = _pulseDuration;
    if (status == AnimationStatus.completed) {
      unawaited(_pulseController.reverse());
    } else if (status == AnimationStatus.dismissed) {
      unawaited(_pulseController.forward());
    }
  }

  Future<dynamic> _onPlatformCall(MethodCall call) async {
    if (call.method != 'sideButtonAction') return null;
    final raw = call.arguments;
    if (raw is! String) return null;
    final action = switch (raw) {
      'snooze' => RA_AlarmActionTypeCodeEnum.Snooze,
      'dismiss' => RA_AlarmActionTypeCodeEnum.Dismiss,
      _ => null,
    };
    if (action == null) return null;
    await _handleAction(action);
    return null;
  }

  Future<void> _syncSideButtonActions() async {
    final settings =
        ref.read(AlarmSideButtonsProvider).valueOrNull ??
        await RA_SettingsService.getSideButtons();
    try {
      await _alarmSoundChannel.invokeMethod('setSideButtonActions', {
        'volumeUp': _actionWireName(settings.volumeUp),
        'volumeDown': _actionWireName(settings.volumeDown),
      });
    } catch (_) {}
  }

  Future<void> _clearSideButtonActions() async {
    try {
      await _alarmSoundChannel.invokeMethod('setSideButtonActions', {
        'volumeUp': 'none',
        'volumeDown': 'none',
      });
    } catch (_) {}
  }

  String _actionWireName(AlarmSideButtonActionEnum action) {
    return switch (action) {
      AlarmSideButtonActionEnum.None => 'none',
      AlarmSideButtonActionEnum.Snooze => 'snooze',
      AlarmSideButtonActionEnum.Dismiss => 'dismiss',
    };
  }

  Future<void> _startAlarmAudio() async {
    await RA_tryAsync(
      () => RA_AudioService.startAlarm(
        audioUri: widget.audioUri,
        vibrate: widget.vibrate,
        volume: widget.volume,
        fadeIn: widget.fadeIn,
      ),
    );
  }

  Future<void> _handleAction(RA_AlarmActionTypeCodeEnum action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await RA_AudioService.stopAlarm();

      // Preview returns to the editor without snooze/dismiss side effects.
      if (widget.isPreview) return;

      final db = ref.read(RA_DatabaseProvider);
      final routine = await db.getRoutineById(widget.routineId);
      final state = await db.getRoutineState(widget.routineId);
      if (state == null) return;

      // handleTransition invokes dismissAlarmUI after IsRinging clears so the
      // activity leaves the lock-screen overlay without killing the engine.
      await RA_AlarmService.handleTransition(
        action: action,
        routineId: widget.routineId,
        db: db,
        routine: routine,
        state: state,
      );

      await RA_NotificationService.cancelNotification(widget.routineId);
    } catch (_) {
      // Transition failures still dismiss the ring page.
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        // Guard canPop: a provider listen may already have popped after
        // IsRinging cleared, and dismissAlarmUI must not race a bare pop.
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop();
        }
      }
    }
  }

  @override
  void dispose() {
    _escalationTimer?.cancel();
    _escalation.dispose();
    _pulseController.removeStatusListener(_onPulseStatus);
    _pulseController.dispose();
    _alarmSoundChannel.setMethodCallHandler(null);
    unawaited(_clearSideButtonActions());
    unawaited(RA_AudioService.stopAlarm());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(AppThemeModeProvider);
    // Keep native key remapping in sync if Settings change while ringing.
    ref.listen(AlarmSideButtonsProvider, (previous, next) {
      next.whenData((_) => unawaited(_syncSideButtonActions()));
    });

    // Notification snooze/dismiss can clear ringing while this page is open.
    // Preview ignores live state so a real ring elsewhere cannot auto close it.
    ref.listen(ActiveRoutineStateProvider(widget.routineId), (previous, next) {
      if (widget.isPreview) return;
      next.whenData((state) {
        if (_busy) return;
        if (state == null || !state.IsRinging) {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        }
      });
    });

    // Scaffold and action chrome stay stable; urgency glow / icon listen to
    // pulse + escalation notifiers, and the clock ticks in its own State.
    // Block system back so Home / Edit cannot cover a live ring.
    // Preview allows back so the editor returns without side effects.
    return PopScope(
      canPop: widget.isPreview,
      child: MediaQuery.withClampedTextScaling(
        minScaleFactor: 0.9,
        maxScaleFactor: 1.2,
        child: Scaffold(
          backgroundColor: RA_ColourStyles.offBlack,
          // Keep the whole ring chrome (glow + controls) above the OS
          // navigation / status bars. viewPadding covers edge-to-edge cases
          // where MediaQuery.padding.bottom is already consumed or zero.
          body: SafeArea(
            maintainBottomViewPadding: true,
            minimum: EdgeInsets.only(
              bottom: MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _RingUrgencyGlow(pulse: _pulse, escalation: _escalation),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(flex: 2),
                    _RingPulseIcon(pulse: _pulse, escalation: _escalation),
                    const SizedBox(height: RA_ShapeStyles.space32),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: RA_ShapeStyles.space24,
                      ),
                      child: RA_FittedText(
                        widget.routineName,
                        alignment: Alignment.center,
                        style: RA_TextStyles.giantFont.copyWith(
                          color: RA_ColourStyles.softCoral,
                        ),
                      ),
                    ),
                    const SizedBox(height: RA_ShapeStyles.space8),
                    Text(
                      'ALARM RINGING',
                      style: RA_TextStyles.mediumFont.copyWith(
                        color: RA_ColourStyles.softCoral.withValues(
                          alpha: 0.85,
                        ),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: RA_ShapeStyles.space16),
                    const _LiveClock(),
                    const Spacer(flex: 2),
                    AnimatedOpacity(
                      duration: RA_ShapeStyles.stateTransitionDuration,
                      opacity: _busy ? 0.45 : 1,
                      child: IgnorePointer(
                        ignoring: _busy,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: RA_ShapeStyles.space24,
                          ),
                          child: _RingActions(
                            layout:
                                ref
                                    .watch(AlarmSnoozeDismissLayoutProvider)
                                    .valueOrNull ??
                                AlarmSnoozeDismissLayoutEnum.Sliders,
                            onSnooze: () => unawaited(
                              _handleAction(RA_AlarmActionTypeCodeEnum.Snooze),
                            ),
                            onDismiss: () => unawaited(
                              _handleAction(RA_AlarmActionTypeCodeEnum.Dismiss),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(
                      height: RA_ShapeStyles.space48 + RA_ShapeStyles.space8,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Snooze/dismiss controls: stacked slide tracks or a side-by-side button row.
class _RingActions extends StatelessWidget {
  final AlarmSnoozeDismissLayoutEnum layout;
  final VoidCallback onSnooze;
  final VoidCallback onDismiss;

  const _RingActions({
    required this.layout,
    required this.onSnooze,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (layout == AlarmSnoozeDismissLayoutEnum.Buttons) {
      return Row(
        children: [
          Expanded(
            child: _RingActionButton(
              key: const Key('ra_ring_snooze'),
              label: 'Snooze',
              semanticsLabel: 'Snooze alarm',
              accent: RA_ColourStyles.secondary,
              glow: RA_ShapeStyles.tealGlow,
              icon: Icons.snooze,
              onPressed: onSnooze,
            ),
          ),
          const SizedBox(width: RA_ShapeStyles.space24),
          Expanded(
            child: _RingActionButton(
              key: const Key('ra_ring_dismiss'),
              label: 'Dismiss',
              semanticsLabel: 'Dismiss alarm',
              accent: RA_ColourStyles.softCoral,
              glow: RA_ShapeStyles.softCoralGlow,
              icon: Icons.alarm_off,
              onPressed: onDismiss,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _SlideToAction(
          key: const Key('ra_ring_snooze'),
          label: 'Slide to snooze',
          semanticsLabel: 'Slide to snooze alarm',
          accent: RA_ColourStyles.secondary,
          glow: RA_ShapeStyles.tealGlow,
          thumbIcon: Icons.snooze,
          onComplete: onSnooze,
        ),
        const SizedBox(height: RA_ShapeStyles.space16),
        _SlideToAction(
          key: const Key('ra_ring_dismiss'),
          label: 'Slide to dismiss',
          semanticsLabel: 'Slide to dismiss alarm',
          accent: RA_ColourStyles.softCoral,
          glow: RA_ShapeStyles.softCoralGlow,
          thumbIcon: Icons.alarm_off,
          onComplete: onDismiss,
        ),
      ],
    );
  }
}

/// Full-width ring action button matching slide-track chrome height and accents.
class _RingActionButton extends StatelessWidget {
  final String label;
  final String semanticsLabel;
  final Color accent;
  final List<BoxShadow> glow;
  final IconData icon;
  final VoidCallback onPressed;

  const _RingActionButton({
    super.key,
    required this.label,
    required this.semanticsLabel,
    required this.accent,
    required this.glow,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: RA_PressScale(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              RA_Haptics.heavyUnawaited();
              onPressed();
            },
            borderRadius: RA_ShapeStyles.largeBorderRadius,
            splashColor: accent.withValues(alpha: 0.2),
            highlightColor: accent.withValues(alpha: 0.1),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: RA_ColourStyles.surface,
                borderRadius: RA_ShapeStyles.largeBorderRadius,
                border: Border.all(
                  color: accent.withValues(alpha: 0.45),
                  width: 1.5,
                ),
                boxShadow: glow,
              ),
              child: SizedBox(
                height: RA_ShapeStyles.minTouchTarget + RA_ShapeStyles.space16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: accent, size: 26),
                    const SizedBox(width: RA_ShapeStyles.space8),
                    Flexible(
                      child: Text(
                        label,
                        style: RA_TextStyles.smallFont.copyWith(color: accent),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-bleed soft coral pulse border. Isolated so the action column does not
/// rebuild on every animation tick or escalation step.
class _RingUrgencyGlow extends StatelessWidget {
  final Animation<double> pulse;
  final ValueNotifier<double> escalation;

  const _RingUrgencyGlow({required this.pulse, required this.escalation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([pulse, escalation]),
      builder: (context, _) {
        final t = pulse.value;
        final e = escalation.value;
        return IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: RA_ColourStyles.softCoral.withValues(
                  alpha: (0.35 + (0.55 * t) + (0.1 * e)).clamp(0.0, 1.0),
                ),
                width: 3 + (3 * t) + (2 * e),
              ),
              boxShadow: [
                BoxShadow(
                  color: RA_ColourStyles.softCoral.withValues(
                    alpha: (0.18 + (0.55 * t) + (0.2 * e)).clamp(0.0, 1.0),
                  ),
                  spreadRadius: 4.0 + (22.0 * t) + (10.0 * e),
                  blurRadius: 16.0 + (40.0 * t) + (16.0 * e),
                ),
              ],
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

/// Isolated pulse icon so title and sliders are not rebuilt from Transform.scale.
class _RingPulseIcon extends StatelessWidget {
  final Animation<double> pulse;
  final ValueNotifier<double> escalation;

  const _RingPulseIcon({required this.pulse, required this.escalation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([pulse, escalation]),
      builder: (context, child) {
        final t = pulse.value;
        final e = escalation.value;
        return Transform.scale(
          scale: 0.9 + (0.18 * t) + (0.06 * e),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: RA_ColourStyles.softCoral.withValues(
                alpha: 0.12 + 0.12 * t + 0.08 * e,
              ),
              border: Border.all(
                color: RA_ColourStyles.softCoral.withValues(
                  alpha: (0.65 + 0.35 * t).clamp(0.0, 1.0),
                ),
                width: 2.5 + (1.5 * t) + e,
              ),
              boxShadow: [
                BoxShadow(
                  color: RA_ColourStyles.softCoral.withValues(
                    alpha: (0.35 + (0.55 * t) + (0.15 * e)).clamp(0.0, 1.0),
                  ),
                  spreadRadius: 4 + (16 * t) + (8 * e),
                  blurRadius: 16 + (32 * t) + (12 * e),
                ),
                BoxShadow(
                  color: RA_ColourStyles.softCoral.withValues(
                    alpha: (0.15 + (0.4 * t) + (0.2 * e)).clamp(0.0, 1.0),
                  ),
                  spreadRadius: 12 + (28 * t) + (16 * e),
                  blurRadius: 40 + (48 * t) + (20 * e),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(RA_ShapeStyles.space32),
              child: child,
            ),
          ),
        );
      },
      child: Icon(Icons.alarm, size: 80, color: RA_ColourStyles.softCoral),
    );
  }
}

/// Per-second clock using tabular figures; does not rebuild the ring page.
class _LiveClock extends StatefulWidget {
  const _LiveClock();

  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      RA_Utils.formatClock(_now),
      style: RA_TextStyles.largeFont.copyWith(
        color: RA_ColourStyles.mutedPrimary,
        fontFeatures: RA_TextStyles.tabularFeatures,
      ),
    );
  }
}

/// Horizontal slide-to-confirm action with heavy haptic on completion.
class _SlideToAction extends StatefulWidget {
  final String label;
  final String semanticsLabel;
  final Color accent;
  final List<BoxShadow> glow;
  final IconData thumbIcon;
  final VoidCallback onComplete;

  const _SlideToAction({
    super.key,
    required this.label,
    required this.semanticsLabel,
    required this.accent,
    required this.glow,
    required this.thumbIcon,
    required this.onComplete,
  });

  @override
  State<_SlideToAction> createState() => _SlideToActionState();
}

class _SlideToActionState extends State<_SlideToAction>
    with SingleTickerProviderStateMixin {
  double _progress = 0;
  bool _completed = false;
  bool _midHapticFired = false;
  bool _dragging = false;
  late final AnimationController _snapController;
  Animation<double>? _snapAnimation;

  static const double _thumbSize = RA_ShapeStyles.minTouchTarget;
  static const double _horizontalPadding = RA_ShapeStyles.space8;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: RA_ShapeStyles.slideSnapDuration,
    );
    _snapController.addListener(() {
      final anim = _snapAnimation;
      if (anim == null) return;
      setState(() => _progress = anim.value);
    });
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details, double trackWidth) {
    if (_completed) return;
    _dragging = true;
    _snapController.stop();
    final maxTravel = (trackWidth - _thumbSize - (_horizontalPadding * 2))
        .clamp(1.0, double.infinity);
    setState(() {
      _progress = (_progress + details.delta.dx / maxTravel).clamp(0.0, 1.0);
    });
    if (!_midHapticFired && _progress >= 0.5) {
      _midHapticFired = true;
      RA_Haptics.heavyUnawaited();
    } else if (_progress < 0.4) {
      _midHapticFired = false;
    }
  }

  void _snapTo(double target) {
    _snapAnimation = Tween<double>(begin: _progress, end: target).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic),
    );
    _snapController.reset();
    unawaited(_snapController.forward());
  }

  void _onDragEnd() {
    if (_completed) return;
    _dragging = false;
    if (_progress >= 0.92) {
      _completed = true;
      _snapTo(1);
      RA_Haptics.heavyUnawaited();
      widget.onComplete();
      return;
    }
    _midHapticFired = false;
    RA_Haptics.heavyUnawaited();
    _snapTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final travel = (width - _thumbSize - (_horizontalPadding * 2)).clamp(
          0.0,
          double.infinity,
        );

        return Semantics(
          button: true,
          label: widget.semanticsLabel,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => _onDragUpdate(d, width),
            onHorizontalDragEnd: (_) => _onDragEnd(),
            child: AnimatedContainer(
              duration: _dragging
                  ? Duration.zero
                  : RA_ShapeStyles.stateTransitionDuration,
              curve: Curves.easeOut,
              height: _thumbSize + RA_ShapeStyles.space16,
              decoration: BoxDecoration(
                color: RA_ColourStyles.surface,
                borderRadius: RA_ShapeStyles.largeBorderRadius,
                border: Border.all(
                  color: widget.accent.withValues(
                    alpha: 0.25 + (0.45 * _progress),
                  ),
                  width: 1.5,
                ),
                boxShadow: _progress > 0.4 ? widget.glow : null,
              ),
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Center(
                    child: Opacity(
                      opacity: (1.0 - _progress).clamp(0.2, 1.0),
                      child: Text(
                        widget.label,
                        style: RA_TextStyles.smallFont.copyWith(
                          color: RA_ColourStyles.mutedPrimary,
                        ),
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(
                      _horizontalPadding + (travel * _progress),
                      0,
                    ),
                    child: SizedBox(
                      width: _thumbSize,
                      height: _thumbSize,
                      child: Padding(
                        padding: const EdgeInsets.all(RA_ShapeStyles.space8),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color.lerp(
                              widget.accent.withValues(alpha: 0.85),
                              widget.accent,
                              _progress,
                            ),
                            borderRadius: RA_ShapeStyles.tinyBorderRadius,
                            boxShadow: widget.glow,
                          ),
                          child: Icon(
                            widget.thumbIcon,
                            color: RA_ColourStyles.onAccent,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
