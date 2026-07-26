import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/components/common/count_daily_skip_dialog.dart';
import 'package:rolling_alarm/components/common/delete_routine_dialog.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/routine/routine_countdown.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/alarm_action_type_code.dart';
import 'package:rolling_alarm/enums/routine_ui_phase.dart';
import 'package:rolling_alarm/navigation/routes.dart';
import 'package:rolling_alarm/pages/alarm_ring.dart';
import 'package:rolling_alarm/pages/routine_summary.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/daily_ring_limit.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:rolling_alarm/utils.dart';

class RA_RoutineCard extends ConsumerWidget {
  final RoutineModel routine;
  final String dbPath;

  const RA_RoutineCard({
    super.key,
    required this.routine,
    required this.dbPath,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Chrome cares about ringing + countdown so teal/coral glows animate with
    // phase without rebuilding on every countdown tick. Also watch whether the
    // next fire is the daily-limit day-start so Dismiss upcoming can hide.
    final phase = ref.watch(
      RoutineUiSnapshotProvider(routine.Id).select((s) => s.phase),
    );
    final hideDismissUpcoming = ref.watch(
      RoutineUiSnapshotProvider(routine.Id).select((s) {
        final next = s.nextTriggerTime;
        if (next == null || !routine.MaxTimesPerDayEnabled) return false;
        return RA_DailyRingLimit.isScheduledAtNextPeriodStart(
          nextTrigger: next,
          dayStartSeconds: routine.DayStartSeconds,
        );
      }),
    );
    final chrome = _chromeFor(phase);

    return Padding(
      padding: const EdgeInsets.only(bottom: RA_ShapeStyles.space16),
      child: _SwipeToConfirmDelete(
        confirm: () =>
            RA_showDeleteRoutineDialog(context, routineName: routine.Name),
        onConfirmed: () => _deleteRoutine(ref),
        background: DecoratedBox(
          decoration: BoxDecoration(
            color: RA_ColourStyles.softCoral,
            borderRadius: RA_ShapeStyles.largeBorderRadius,
          ),
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: RA_ShapeStyles.space24),
              child: Icon(
                Icons.delete_outline,
                color: RA_ColourStyles.offBlack,
                size: 28,
              ),
            ),
          ),
        ),
        child: AnimatedContainer(
          duration: RA_ShapeStyles.stateTransitionDuration,
          curve: Curves.easeInOut,
          decoration: RA_ShapeStyles.elevatedSurface(
            fill: chrome.fill,
            borderColor: chrome.border,
            borderWidth: chrome.borderWidth,
            boxShadow: chrome.glow,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: RA_ShapeStyles.largeBorderRadius,
            child: InkWell(
              borderRadius: RA_ShapeStyles.largeBorderRadius,
              splashColor: chrome.splash,
              highlightColor: chrome.highlight,
              onTap: () {
                RA_Haptics.heavyUnawaited();
                final isRinging = phase == RA_RoutineUiPhase.ringing;
                unawaited(
                  Navigator.push(
                    context,
                    isRinging
                        ? RA_Routes.alarmRing(
                            AlarmRingPage(
                              routineId: routine.Id,
                              routineName: routine.Name,
                              audioUri: routine.AudioUri,
                              vibrate: routine.Vibrate,
                              volume: routine.Volume,
                            ),
                          )
                        : RA_Routes.fade(
                            RoutineSummaryPage(
                              routineId: routine.Id,
                              dbPath: dbPath,
                            ),
                          ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(RA_ShapeStyles.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            routine.Name,
                            style: RA_TextStyles.mediumFont,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: RA_ShapeStyles.space8),
                        Text(
                          RA_Utils.formatInterval(routine.IntervalSeconds),
                          style: RA_TextStyles.intervalDigitsFont,
                        ),
                      ],
                    ),
                    const SizedBox(height: RA_ShapeStyles.space8),
                    _TodayRingCount(routine: routine),
                    const SizedBox(height: RA_ShapeStyles.space16),
                    _RoutineCardStatus(routineId: routine.Id),
                    if (!hideDismissUpcoming) ...[
                      const SizedBox(height: RA_ShapeStyles.space16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: RA_IconTextButton(
                          icon: Icons.skip_next,
                          label: 'Dismiss upcoming',
                          onTap: () => unawaited(_handleSkip(context, ref)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _deleteRoutine(WidgetRef ref) async {
    final deleted = await RA_tryAsync(() async {
      final db = ref.read(RA_DatabaseProvider);
      await RA_AlarmService.cancel(routine.Id);
      await db.softDeleteRoutine(routine.Id);
      return true;
    });
    return deleted == true;
  }

  Future<void> _handleSkip(BuildContext context, WidgetRef ref) async {
    final countTowardsDaily = await RA_showCountDailySkipDialog(context);
    if (countTowardsDaily == null) return;

    await RA_tryAsync(() async {
      final db = ref.read(RA_DatabaseProvider);
      final state = await db.getRoutineState(routine.Id);
      if (state == null) return;
      await RA_AlarmService.handleTransition(
        action: RA_AlarmActionTypeCodeEnum.Skip,
        routineId: routine.Id,
        db: db,
        routine: routine,
        state: state,
        countSkipTowardsDaily: countTowardsDaily,
      );
    });
  }
}

/// Swipe left to reveal delete. On release past the threshold, the confirm
/// dialog opens immediately (no wait for a slide off animation).
class _SwipeToConfirmDelete extends StatefulWidget {
  final Widget child;
  final Widget background;
  final Future<bool?> Function() confirm;
  final Future<bool> Function() onConfirmed;

  const _SwipeToConfirmDelete({
    required this.child,
    required this.background,
    required this.confirm,
    required this.onConfirmed,
  });

  @override
  State<_SwipeToConfirmDelete> createState() => _SwipeToConfirmDeleteState();
}

class _SwipeToConfirmDeleteState extends State<_SwipeToConfirmDelete>
    with SingleTickerProviderStateMixin {
  static const double _dismissFraction = 0.4;

  late final AnimationController _controller;
  double _width = 1;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _animateTo(double target) {
    return _controller.animateTo(
      target,
      duration: RA_ShapeStyles.slideSnapDuration,
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _onDragEnd(double velocity) async {
    if (_busy) return;

    final pastThreshold = -_controller.value >= _width * _dismissFraction;
    final flingToDelete = velocity < -700 && _controller.value < 0;
    if (!pastThreshold && !flingToDelete) {
      await _animateTo(0);
      return;
    }

    _busy = true;
    RA_Haptics.heavyUnawaited();

    final confirmed = await widget.confirm();
    if (!mounted) return;

    if (confirmed == true) {
      await _animateTo(-_width);
      if (!mounted) return;
      final deleted = await widget.onConfirmed();
      if (!mounted) return;
      if (!deleted) {
        await _animateTo(0);
      }
    } else {
      await _animateTo(0);
    }

    if (mounted) _busy = false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        return GestureDetector(
          onHorizontalDragStart: (_) {
            if (_busy) return;
            _controller.stop();
          },
          onHorizontalDragUpdate: (details) {
            if (_busy) return;
            _controller.value = (_controller.value + details.delta.dx).clamp(
              -_width,
              0.0,
            );
          },
          onHorizontalDragEnd: (details) {
            if (_busy) return;
            unawaited(_onDragEnd(details.primaryVelocity ?? 0));
          },
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Stack(
                children: [
                  Positioned.fill(child: widget.background),
                  Transform.translate(
                    offset: Offset(_controller.value, 0),
                    child: child,
                  ),
                ],
              );
            },
            child: widget.child,
          ),
        );
      },
    );
  }
}

class _CardChrome {
  final Color fill;
  final Color border;
  final double borderWidth;
  final List<BoxShadow>? glow;
  final Color splash;
  final Color highlight;

  const _CardChrome({
    required this.fill,
    required this.border,
    required this.borderWidth,
    required this.glow,
    required this.splash,
    required this.highlight,
  });
}

_CardChrome _chromeFor(RA_RoutineUiPhase phase) => switch (phase) {
  RA_RoutineUiPhase.ringing => _CardChrome(
    fill: RA_ColourStyles.softCoral.withValues(alpha: 0.08),
    border: RA_ColourStyles.softCoral.withValues(alpha: 0.7),
    borderWidth: 1.5,
    glow: RA_ShapeStyles.softCoralGlow,
    splash: RA_ColourStyles.softCoral.withValues(alpha: 0.12),
    highlight: RA_ColourStyles.softCoral.withValues(alpha: 0.05),
  ),
  RA_RoutineUiPhase.countingDown => _CardChrome(
    fill: RA_ColourStyles.secondary.withValues(alpha: 0.04),
    border: RA_ColourStyles.secondary.withValues(alpha: 0.35),
    borderWidth: 1.5,
    glow: RA_ShapeStyles.tealGlow,
    splash: RA_ColourStyles.secondary.withValues(alpha: 0.1),
    highlight: RA_ColourStyles.secondary.withValues(alpha: 0.04),
  ),
  RA_RoutineUiPhase.idle ||
  RA_RoutineUiPhase.notScheduled ||
  RA_RoutineUiPhase.loading ||
  RA_RoutineUiPhase.error => _CardChrome(
    fill: RA_ColourStyles.offBlack,
    border: RA_ShapeStyles.idleSurfaceBorder,
    borderWidth: 1,
    glow: null,
    splash: RA_ColourStyles.secondary.withValues(alpha: 0.14),
    highlight: RA_ColourStyles.secondary.withValues(alpha: 0.06),
  ),
};

/// How many times this routine has rung in the current day period.
class _TodayRingCount extends ConsumerWidget {
  final RoutineModel routine;

  const _TodayRingCount({required this.routine});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(
      ActiveRoutineStateProvider(routine.Id).select((async) {
        final state = async.valueOrNull;
        if (state == null) return 0;
        return RA_DailyRingLimit.countForDay(
          timesRingToday: state.TimesRingToday,
          timesRingDay: state.TimesRingDay,
          now: DateTime.now(),
          dayStartSeconds: routine.DayStartSeconds,
        );
      }),
    );

    final label = count == 1 ? '1 time today' : '$count times today';
    return Text(
      label,
      style: RA_TextStyles.tinyFont.copyWith(
        color: RA_ColourStyles.mutedPrimary,
      ),
    );
  }
}

/// Status region only. Phase changes animate here; countdown ticks stay inside
/// [RA_Countdown] so this widget does not rebuild every second.
class _RoutineCardStatus extends ConsumerWidget {
  final int routineId;

  const _RoutineCardStatus({required this.routineId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Full snapshot is equality-gated on phase + next trigger only, so
    // per-second countdown ticks (CountdownProvider) never reach this widget.
    final snapshot = ref.watch(RoutineUiSnapshotProvider(routineId));
    final mutedStyle = RA_TextStyles.smallFont.copyWith(
      color: RA_ColourStyles.mutedPrimary,
    );

    return AnimatedSwitcher(
      duration: RA_ShapeStyles.stateTransitionDuration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topLeft,
        children: <Widget>[...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          alignment: Alignment.topCenter,
          child: child,
        ),
      ),
      child: _statusChild(snapshot, mutedStyle),
    );
  }

  Widget _statusChild(RA_RoutineUiSnapshot snapshot, TextStyle mutedStyle) {
    switch (snapshot.phase) {
      case RA_RoutineUiPhase.notScheduled:
      case RA_RoutineUiPhase.idle:
        return Text(
          snapshot.phase == RA_RoutineUiPhase.idle ? 'Idle' : 'Not scheduled',
          key: ValueKey(snapshot.phase.name),
          style: mutedStyle,
        );
      case RA_RoutineUiPhase.ringing:
        return Text(
          'RINGING',
          key: const ValueKey('ringing'),
          style: RA_TextStyles.mediumFont.copyWith(
            color: RA_ColourStyles.softCoral,
          ),
        );
      case RA_RoutineUiPhase.countingDown:
        final next = snapshot.nextTriggerTime!;
        return Column(
          key: ValueKey('next_${next.millisecondsSinceEpoch}'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RA_Countdown(nextTriggerTime: next),
            const SizedBox(height: RA_ShapeStyles.space8),
            Text(
              'Next: ${RA_Utils.formatTime(next)}',
              style: RA_TextStyles.timestampFont,
            ),
          ],
        );
      case RA_RoutineUiPhase.loading:
        return SizedBox(
          key: const ValueKey('loading'),
          height: RA_ShapeStyles.space24,
          width: RA_ShapeStyles.space24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: RA_ColourStyles.secondary,
          ),
        );
      case RA_RoutineUiPhase.error:
        return Text(
          'Unavailable',
          key: const ValueKey('error'),
          style: RA_TextStyles.smallFont.copyWith(
            color: RA_ColourStyles.softCoral.withValues(alpha: 0.85),
          ),
        );
    }
  }
}
