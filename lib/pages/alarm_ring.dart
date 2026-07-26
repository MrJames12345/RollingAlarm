import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/components/common/fitted_text.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/enums/alarm_action_type_code.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/audio.dart';
import 'package:rolling_alarm/services/notification.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:rolling_alarm/utils.dart';

class AlarmRingPage extends ConsumerStatefulWidget {
  final int routineId;
  final String routineName;
  final String? audioUri;
  final bool vibrate;
  final int volume;

  const AlarmRingPage({
    super.key,
    required this.routineId,
    required this.routineName,
    this.audioUri,
    this.vibrate = true,
    this.volume = 100,
  });

  @override
  ConsumerState<AlarmRingPage> createState() => _AlarmRingPageState();
}

class _AlarmRingPageState extends ConsumerState<AlarmRingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;
  late final ValueNotifier<double> _escalation;
  Timer? _escalationTimer;

  /// 0.0 at open, climbs toward 1.0 so the coral pulse grows more aggressive.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    RA_Haptics.heavyUnawaited();
    _escalation = ValueNotifier(0);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
    );
    unawaited(_pulseController.repeat(reverse: true));
    _pulse = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);
    _escalationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || _escalation.value >= 1) {
        if (_escalation.value >= 1) _escalationTimer?.cancel();
        return;
      }
      final next = (_escalation.value + 0.08).clamp(0.0, 1.0);
      _escalation.value = next;
      // Quicken the pulse as urgency climbs without rebuilding the page shell.
      final ms = (780 - (280 * next)).round();
      _pulseController.duration = Duration(milliseconds: ms);
      unawaited(_pulseController.repeat(reverse: true));
    });
    unawaited(_startAlarmAudio());
  }

  Future<void> _startAlarmAudio() async {
    await RA_tryAsync(
      () => RA_AudioService.startAlarm(
        audioUri: widget.audioUri,
        vibrate: widget.vibrate,
        volume: widget.volume,
      ),
    );
  }

  Future<void> _handleAction(RA_AlarmActionTypeCodeEnum action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await RA_AudioService.stopAlarm();

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
    _pulseController.dispose();
    unawaited(RA_AudioService.stopAlarm());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Notification snooze/dismiss can clear ringing while this page is open.
    ref.listen(ActiveRoutineStateProvider(widget.routineId), (previous, next) {
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
    return PopScope(
      canPop: false,
      child: MediaQuery.withClampedTextScaling(
        minScaleFactor: 0.9,
        maxScaleFactor: 1.2,
        child: Scaffold(
          backgroundColor: RA_ColourStyles.offBlack,
          body: Stack(
            fit: StackFit.expand,
            children: [
              _RingUrgencyGlow(pulse: _pulse, escalation: _escalation),
              SafeArea(
                child: Column(
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
                            horizontal: RA_ShapeStyles.space16,
                          ),
                          child: Column(
                            children: [
                              _SlideToAction(
                                key: const Key('ra_ring_snooze'),
                                label: 'Slide to snooze',
                                semanticsLabel: 'Slide to snooze alarm',
                                accent: RA_ColourStyles.secondary,
                                glow: RA_ShapeStyles.tealGlow,
                                thumbIcon: Icons.snooze,
                                onComplete: () => unawaited(
                                  _handleAction(
                                    RA_AlarmActionTypeCodeEnum.Snooze,
                                  ),
                                ),
                              ),
                              const SizedBox(height: RA_ShapeStyles.space16),
                              _SlideToAction(
                                key: const Key('ra_ring_dismiss'),
                                label: 'Slide to dismiss',
                                semanticsLabel: 'Slide to dismiss alarm',
                                accent: RA_ColourStyles.softCoral,
                                glow: RA_ShapeStyles.softCoralGlow,
                                thumbIcon: Icons.alarm_off,
                                onComplete: () => unawaited(
                                  _handleAction(
                                    RA_AlarmActionTypeCodeEnum.Dismiss,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: RA_ShapeStyles.space48),
                  ],
                ),
              ),
            ],
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
        color: RA_ColourStyles.primary.withValues(alpha: 0.55),
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
                            color: RA_ColourStyles.offBlack,
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
