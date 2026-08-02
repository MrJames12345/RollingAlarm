import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/components/common/adjust_today_max_dialog.dart';
import 'package:rolling_alarm/components/common/count_daily_skip_dialog.dart';
import 'package:rolling_alarm/components/common/delete_routine_dialog.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/reset_today_counter_dialog.dart';
import 'package:rolling_alarm/components/common/routine_card_actions_dialog.dart';
import 'package:rolling_alarm/components/routine/routine_countdown.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/alarm_action_type_code.dart';
import 'package:rolling_alarm/enums/app_theme_mode.dart';
import 'package:rolling_alarm/enums/routine_swipe_action.dart';
import 'package:rolling_alarm/enums/routine_ui_phase.dart';
import 'package:rolling_alarm/navigation/routes.dart';
import 'package:rolling_alarm/pages/alarm_ring.dart';
import 'package:rolling_alarm/pages/routine_edit.dart';
import 'package:rolling_alarm/pages/routine_summary.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/daily_ring_limit.dart';
import 'package:rolling_alarm/services/routine_duplicate.dart';
import 'package:rolling_alarm/services/weekday_schedule.dart';
import 'package:rolling_alarm/services/widget.dart';
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
    // phase without rebuilding on every countdown tick.
    final phase = ref.watch(
      RoutineUiSnapshotProvider(routine.Id).select((s) => s.phase),
    );
    final isPaused = phase == RA_RoutineUiPhase.paused;
    final isMuted = phase == RA_RoutineUiPhase.muted;
    // Buttons are hidden when paused to keep the card compact, unless
    // they are Pause/Resume, but for simplicity we keep the old behavior.
    final showButtons = !isPaused;
    final chrome = _chromeFor(phase);
    final swipeActions =
        ref.watch(RoutineSwipeActionsProvider).valueOrNull ??
        const RoutineSwipeActionsSettings();
    final cardButtons =
        ref.watch(RoutineCardButtonsProvider).valueOrNull ??
        const RoutineCardButtonsSettings();

    return Padding(
      padding: const EdgeInsets.only(bottom: RA_ShapeStyles.space16),
      child: _SwipeRoutineActions(
        // Tie swipe State to this routine so a delete does not leave the
        // reveal open on the next tile that reuses this list slot.
        key: ValueKey(routine.Id),
        leftAction: swipeActions.left,
        rightAction: swipeActions.right,
        isPaused: isPaused,
        resetIntervalAllowed: showButtons,
        confirmDelete: () =>
            RA_showDeleteRoutineDialog(context, routineName: routine.Name),
        onDeleteConfirmed: () => _deleteRoutine(ref),
        onMute: () => _toggleMute(ref),
        onPause: () => _togglePause(ref),
        onResetInterval: () => _handleResetInterval(context, ref),
        onAddForToday: () => _adjustTodayMax(context, ref),
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
                              fadeIn: routine.FadeIn,
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
              onLongPress: () => unawaited(
                _openActionsMenu(
                  context,
                  ref,
                  isMuted: isMuted,
                  isPaused: isPaused,
                  showResetInterval: showButtons,
                ),
              ),
              child: AnimatedOpacity(
                duration: RA_ShapeStyles.stateTransitionDuration,
                opacity: isPaused ? 0.62 : (isMuted ? 0.85 : 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(RA_ShapeStyles.space16),
                      child: Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      routine.Name,
                                      style: RA_TextStyles.mediumFont.copyWith(
                                        color: isPaused
                                            ? RA_ColourStyles.mutedPrimary
                                            : null,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: RA_ShapeStyles.space8),
                                  Text(
                                    RA_Utils.formatInterval(
                                      routine.IntervalSeconds,
                                    ),
                                    style: RA_TextStyles.intervalDigitsFont
                                        .copyWith(
                                          color: isPaused
                                              ? RA_ColourStyles.faintPrimary
                                              : null,
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: RA_ShapeStyles.space8),
                              _TodayRingCount(
                                routine: routine,
                                muted: isPaused,
                              ),
                              const SizedBox(height: RA_ShapeStyles.space16),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (showButtons)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        right: 8,
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius: RA_ShapeStyles.tinyBorderRadius,
                                          onTap: () => _runCardButtonAction(context, ref, cardButtons.left),
                                          child: Padding(
                                            padding: const EdgeInsets.all(4),
                                            child: Icon(
                                              cardButtons.left.icon(isPaused: isPaused),
                                              color: RA_ColourStyles.secondary,
                                              size: 28,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    child: _RoutineCardStatus(routineId: routine.Id),
                                  ),
                                  if (showButtons)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 8,
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius: RA_ShapeStyles.tinyBorderRadius,
                                          onTap: () => _runCardButtonAction(context, ref, cardButtons.right),
                                          child: Padding(
                                            padding: const EdgeInsets.all(4),
                                            child: Icon(
                                              cardButtons.right.icon(isPaused: isPaused),
                                              color: RA_ColourStyles.secondary,
                                              size: 28,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          if (isMuted)
                            const Positioned(
                              right: 0,
                              bottom: 0,
                              child: Icon(
                                Icons.notifications_off_rounded,
                                color: RA_ColourStyles.sleepIndigo,
                                size: 20,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (!RA_WeekdaySchedule.isEveryDay(routine.EnabledWeekdays))
                      _RoutineCardWeekdays(
                        enabledWeekdays: routine.EnabledWeekdays,
                        muted: isPaused,
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

  Future<void> _runCardButtonAction(
    BuildContext context,
    WidgetRef ref,
    RoutineSwipeActionEnum action,
  ) async {
    switch (action) {
      case RoutineSwipeActionEnum.Mute:
        await _toggleMute(ref);
      case RoutineSwipeActionEnum.Pause:
        await _togglePause(ref);
      case RoutineSwipeActionEnum.ResetInterval:
        await _handleResetInterval(context, ref);
      case RoutineSwipeActionEnum.AddForToday:
        await _adjustTodayMax(context, ref);
      case RoutineSwipeActionEnum.Delete:
        final confirmed = await RA_showDeleteRoutineDialog(
          context,
          routineName: routine.Name,
        );
        if (confirmed == true && context.mounted) {
          await _deleteRoutine(ref);
        }
    }
  }

  Future<bool> _deleteRoutine(WidgetRef ref) async {
    final deleted = await RA_tryAsync(() async {
      final db = ref.read(RA_DatabaseProvider);
      await RA_AlarmService.cancel(routine.Id);
      await db.softDeleteRoutine(routine.Id);
      await RA_WidgetService.updateWidgetState(db: db);
      return true;
    });
    return deleted == true;
  }

  Future<void> _togglePause(WidgetRef ref) async {
    await RA_tryAsync(() async {
      final db = ref.read(RA_DatabaseProvider);
      final paused =
          ref.read(RoutineUiSnapshotProvider(routine.Id)).phase ==
          RA_RoutineUiPhase.paused;
      if (paused) {
        await RA_AlarmService.resumeRoutine(
          routineId: routine.Id,
          db: db,
          routine: routine,
          dbPath: dbPath,
        );
      } else {
        await RA_AlarmService.pauseRoutine(
          routineId: routine.Id,
          db: db,
          routine: routine,
          dbPath: dbPath,
        );
      }
    });
  }

  Future<void> _toggleMute(WidgetRef ref) async {
    await RA_tryAsync(() async {
      final db = ref.read(RA_DatabaseProvider);
      final muted =
          ref.read(RoutineUiSnapshotProvider(routine.Id)).phase ==
          RA_RoutineUiPhase.muted;
      if (muted) {
        await RA_AlarmService.unmuteRoutine(routineId: routine.Id, db: db);
      } else {
        await RA_AlarmService.muteRoutine(
          routineId: routine.Id,
          db: db,
          routine: routine,
          dbPath: dbPath,
        );
      }
    });
  }

  Future<void> _handleResetInterval(BuildContext context, WidgetRef ref) async {
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

  Future<void> _adjustTodayMax(BuildContext context, WidgetRef ref) async {
    final db = ref.read(RA_DatabaseProvider);
    final state = await db.getRoutineState(routine.Id);
    if (state == null || !context.mounted) return;

    final now = DateTime.now();
    final samePeriod = state.TimesRingDay != null && 
        RA_DailyRingLimit.isSamePeriod(state.TimesRingDay!, now, routine.DayStartSeconds);
    final currentExtra = samePeriod ? state.ExtraMaxTimesToday : 0;
    
    final currentMax = (routine.MaxTimesPerDayEnabled ? routine.MaxTimesPerDay : 0) + currentExtra;

    final newTotalMax = await RA_showAdjustTodayMaxDialog(context, currentMax: currentMax);
    if (newTotalMax == null || newTotalMax < 0) return;

    RA_Haptics.heavyUnawaited();
    await RA_tryAsync(() async {
      await RA_AlarmService.setTodayMaxCount(
        routineId: routine.Id,
        db: db,
        routine: routine,
        dbPath: dbPath,
        newTotalMax: newTotalMax,
      );
    });
  }

  Future<void> _openActionsMenu(
    BuildContext context,
    WidgetRef ref, {
    required bool isMuted,
    required bool isPaused,
    required bool showResetInterval,
  }) async {
    RA_Haptics.heavyUnawaited();
    final action = await RA_showRoutineCardActionsDialog(
      context,
      routineName: routine.Name,
      isMuted: isMuted,
      isPaused: isPaused,
      showResetInterval: showResetInterval,
    );
    if (action == null || !context.mounted) return;

    switch (action) {
      case RA_RoutineCardMenuAction.mute:
        await _toggleMute(ref);
      case RA_RoutineCardMenuAction.pause:
        await _togglePause(ref);
      case RA_RoutineCardMenuAction.resetInterval:
        await _handleResetInterval(context, ref);
      case RA_RoutineCardMenuAction.addTodayCount:
        await _adjustTodayMax(context, ref);
        break;
      case RA_RoutineCardMenuAction.edit:
        await Navigator.push(
          context,
          RA_Routes.fade(
            RoutineEditPage(dbPath: dbPath, existingRoutine: routine),
          ),
        );
      case RA_RoutineCardMenuAction.duplicate:
        await _duplicateRoutine(ref);
      case RA_RoutineCardMenuAction.resetTodayCounter:
        await _resetTodayCounter(context, ref);
      case RA_RoutineCardMenuAction.delete:
        final confirmed = await RA_showDeleteRoutineDialog(
          context,
          routineName: routine.Name,
        );
        if (confirmed == true) {
          await _deleteRoutine(ref);
        }
    }
  }

  Future<void> _duplicateRoutine(WidgetRef ref) async {
    RA_Haptics.heavyUnawaited();
    await RA_tryAsync(() async {
      final db = ref.read(RA_DatabaseProvider);
      await RA_RoutineDuplicateService.duplicate(
        db: db,
        source: routine,
        dbPath: dbPath,
      );
    });
  }

  Future<void> _resetTodayCounter(BuildContext context, WidgetRef ref) async {
    final confirmed = await RA_showResetTodayCounterDialog(context);
    if (confirmed != true) return;

    RA_Haptics.heavyUnawaited();
    await RA_tryAsync(() async {
      final db = ref.read(RA_DatabaseProvider);
      await RA_AlarmService.resetTodayCounter(
        routineId: routine.Id,
        db: db,
        routine: routine,
        dbPath: dbPath,
      );
    });
  }
}

/// Swipe left/right to run the configured home-card actions.
class _SwipeRoutineActions extends StatefulWidget {
  final Widget child;
  final RoutineSwipeActionEnum leftAction;
  final RoutineSwipeActionEnum rightAction;
  final bool isPaused;
  final bool resetIntervalAllowed;
  final Future<bool?> Function() confirmDelete;
  final Future<bool> Function() onDeleteConfirmed;
  final Future<void> Function() onMute;
  final Future<void> Function() onPause;
  final Future<void> Function() onResetInterval;
  final Future<void> Function() onAddForToday;

  const _SwipeRoutineActions({
    super.key,
    required this.child,
    required this.leftAction,
    required this.rightAction,
    required this.isPaused,
    required this.resetIntervalAllowed,
    required this.confirmDelete,
    required this.onDeleteConfirmed,
    required this.onMute,
    required this.onPause,
    required this.onResetInterval,
    required this.onAddForToday,
  });

  @override
  State<_SwipeRoutineActions> createState() => _SwipeRoutineActionsState();
}

class _SwipeRoutineActionsState extends State<_SwipeRoutineActions>
    with SingleTickerProviderStateMixin {
  static const double _actionFraction = 0.4;

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

  bool _actionAvailable(RoutineSwipeActionEnum action) {
    if (action == RoutineSwipeActionEnum.ResetInterval) {
      return widget.resetIntervalAllowed;
    }
    return true;
  }

  Future<void> _onDragEnd(double velocity) async {
    if (_busy) return;

    final value = _controller.value;
    final towardLeft = value < 0 || (value == 0 && velocity < 0);
    final action = towardLeft ? widget.leftAction : widget.rightAction;
    final signedThreshold = _width * _actionFraction;
    final pastThreshold = towardLeft
        ? -value >= signedThreshold
        : value >= signedThreshold;
    final fling = towardLeft
        ? velocity < -700 && value < 0
        : velocity > 700 && value > 0;

    if ((!pastThreshold && !fling) || !_actionAvailable(action)) {
      await _animateTo(0);
      return;
    }

    _busy = true;
    RA_Haptics.heavyUnawaited();

    if (action == RoutineSwipeActionEnum.Delete) {
      final confirmed = await widget.confirmDelete();
      if (!mounted) return;
      if (confirmed == true) {
        await _animateTo(towardLeft ? -_width : _width);
        if (!mounted) return;
        final deleted = await widget.onDeleteConfirmed();
        if (!mounted) return;
        if (!deleted) await _animateTo(0);
      } else {
        await _animateTo(0);
      }
    } else {
      await _runAction(action);
      if (!mounted) return;
      await _animateTo(0);
    }

    if (mounted) _busy = false;
  }

  Future<void> _runAction(RoutineSwipeActionEnum action) async {
    switch (action) {
      case RoutineSwipeActionEnum.Mute:
        await widget.onMute();
      case RoutineSwipeActionEnum.Pause:
        await widget.onPause();
      case RoutineSwipeActionEnum.ResetInterval:
        await widget.onResetInterval();
      case RoutineSwipeActionEnum.AddForToday:
        await widget.onAddForToday();
      case RoutineSwipeActionEnum.Delete:
        break;
    }
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
              _width,
            );
          },
          onHorizontalDragEnd: (details) {
            if (_busy) return;
            unawaited(_onDragEnd(details.primaryVelocity ?? 0));
          },
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final value = _controller.value;
              return Stack(
                children: [
                  if (value < 0)
                    Positioned.fill(
                      child: _SwipeActionBackground(
                        action: widget.leftAction,
                        alignEnd: true,
                        isPaused: widget.isPaused,
                      ),
                    ),
                  if (value > 0)
                    Positioned.fill(
                      child: _SwipeActionBackground(
                        action: widget.rightAction,
                        alignEnd: false,
                        isPaused: widget.isPaused,
                      ),
                    ),
                  Transform.translate(offset: Offset(value, 0), child: child),
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

/// Coloured swipe reveal with action icon on the exposed edge.
class _SwipeActionBackground extends StatelessWidget {
  final RoutineSwipeActionEnum action;
  final bool alignEnd;
  final bool isPaused;

  const _SwipeActionBackground({
    required this.action,
    required this.alignEnd,
    required this.isPaused,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: action.color(isPaused: isPaused),
        borderRadius: RA_ShapeStyles.largeBorderRadius,
      ),
      child: Align(
        alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.only(
            left: alignEnd ? 0 : RA_ShapeStyles.space24,
            right: alignEnd ? RA_ShapeStyles.space24 : 0,
          ),
          child: Icon(
            action.icon(isPaused: isPaused),
            color: action.iconColor,
            size: 28,
          ),
        ),
      ),
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

_CardChrome _chromeFor(RA_RoutineUiPhase phase) {
  final isLight = RA_ColourStyles.mode == AppThemeModeEnum.Light;
  final fill = RA_ColourStyles.cardFill;
  return switch (phase) {
    RA_RoutineUiPhase.ringing => _CardChrome(
      fill: fill,
      border: RA_ColourStyles.softCoral.withValues(alpha: 0.7),
      borderWidth: 1.5,
      glow: RA_ShapeStyles.softCoralGlow,
      splash: RA_ColourStyles.softCoral.withValues(alpha: 0.12),
      highlight: RA_ColourStyles.softCoral.withValues(alpha: 0.05),
    ),
    RA_RoutineUiPhase.countingDown => _CardChrome(
      fill: fill,
      border: RA_ColourStyles.secondary.withValues(alpha: isLight ? 0.45 : 0.35),
      borderWidth: 1.5,
      glow: RA_ShapeStyles.tealGlow,
      splash: RA_ColourStyles.secondary.withValues(alpha: 0.1),
      highlight: RA_ColourStyles.secondary.withValues(alpha: 0.04),
    ),
    RA_RoutineUiPhase.muted => _CardChrome(
      fill: fill,
      border: RA_ColourStyles.sleepIndigo.withValues(alpha: isLight ? 0.55 : 0.4),
      borderWidth: 1.5,
      glow: null,
      splash: RA_ColourStyles.sleepIndigo.withValues(alpha: 0.12),
      highlight: RA_ColourStyles.sleepIndigo.withValues(alpha: 0.05),
    ),
    RA_RoutineUiPhase.paused => _CardChrome(
      fill: fill,
      border: RA_ColourStyles.sleepIndigo.withValues(alpha: isLight ? 0.55 : 0.45),
      borderWidth: 1.5,
      glow: null,
      splash: RA_ColourStyles.sleepIndigo.withValues(alpha: 0.12),
      highlight: RA_ColourStyles.sleepIndigo.withValues(alpha: 0.05),
    ),
    RA_RoutineUiPhase.idle ||
    RA_RoutineUiPhase.notScheduled ||
    RA_RoutineUiPhase.loading ||
    RA_RoutineUiPhase.error => _CardChrome(
      fill: fill,
      border: RA_ShapeStyles.idleSurfaceBorder,
      borderWidth: 1,
      glow: null,
      splash: RA_ColourStyles.secondary.withValues(alpha: 0.14),
      highlight: RA_ColourStyles.secondary.withValues(alpha: 0.06),
    ),
  };
}

/// Compact MTWTFSS strip along the card bottom when any weekday is disabled.
class _RoutineCardWeekdays extends StatelessWidget {
  final int enabledWeekdays;
  final bool muted;

  const _RoutineCardWeekdays({
    required this.enabledWeekdays,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RA_ShapeStyles.space16,
        0,
        RA_ShapeStyles.space16,
        RA_ShapeStyles.space16,
      ),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++) ...[
            if (i > 0) const SizedBox(width: RA_ShapeStyles.space8),
            Expanded(
              child: _WeekdayLetter(
                label: RA_WeekdaySchedule.dayLabels[i],
                enabled: RA_WeekdaySchedule.isEnabled(enabledWeekdays, i + 1),
                muted: muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeekdayLetter extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool muted;

  const _WeekdayLetter({
    required this.label,
    required this.enabled,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: TextAlign.center,
      style: RA_TextStyles.tinyFont.copyWith(
        color: enabled
            ? (muted ? RA_ColourStyles.mutedPrimary : RA_ColourStyles.primary)
            : RA_ColourStyles.faintPrimary,
        fontWeight: enabled ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }
}

/// How many times this routine has rung in the current day period.
class _TodayRingCount extends ConsumerWidget {
  final RoutineModel routine;
  final bool muted;

  const _TodayRingCount({required this.routine, this.muted = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(
      ActiveRoutineStateProvider(routine.Id).select((async) {
        final state = async.valueOrNull;
        if (state == null) return (count: 0, extra: 0);
        final now = DateTime.now();
        final count = RA_DailyRingLimit.countForDay(
          timesRingToday: state.TimesRingToday,
          timesRingDay: state.TimesRingDay,
          now: now,
          dayStartSeconds: routine.DayStartSeconds,
        );
        final samePeriod = state.TimesRingDay != null && 
            RA_DailyRingLimit.isSamePeriod(state.TimesRingDay!, now, routine.DayStartSeconds);
        final extra = samePeriod ? state.ExtraMaxTimesToday : 0;
        return (count: count, extra: extra);
      }),
    );

    final count = data.count;
    final maxTimes = routine.MaxTimesPerDay + data.extra;

    final label = routine.MaxTimesPerDayEnabled
        ? '$count/$maxTimes times today'
        : count == 1
        ? '1 time today'
        : '$count times today';
    return Text(
      label,
      style: RA_TextStyles.tinyFont.copyWith(
        color: muted
            ? RA_ColourStyles.faintPrimary
            : RA_ColourStyles.mutedPrimary,
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
    // Full snapshot is equality-gated on phase + next trigger + pause only, so
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
      case RA_RoutineUiPhase.muted:
        final next = snapshot.nextTriggerTime!;
        return Column(
          key: ValueKey(
            '${snapshot.phase.name}_${next.millisecondsSinceEpoch}',
          ),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RA_Countdown(nextTriggerTime: next),
            const SizedBox(height: RA_ShapeStyles.space8),
            Text(
              RA_Utils.formatNextFireCaption(
                next,
                muted: snapshot.phase == RA_RoutineUiPhase.muted,
              ),
              style: RA_TextStyles.timestampFont,
            ),
          ],
        );
      case RA_RoutineUiPhase.paused:
        final remaining = snapshot.pausedRemaining;
        if (remaining == null) {
          return Text(
            'Paused',
            key: ValueKey(
              'paused_idle_${snapshot.pausedAt?.millisecondsSinceEpoch}',
            ),
            style: mutedStyle,
          );
        }
        return RA_Countdown(
          key: ValueKey(
            'paused_${snapshot.pausedAt?.millisecondsSinceEpoch}_'
            '${snapshot.nextTriggerTime?.millisecondsSinceEpoch}',
          ),
          frozenRemaining: remaining,
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
