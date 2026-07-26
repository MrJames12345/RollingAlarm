import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/components/common/delete_routine_dialog.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/routine/routine_countdown.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/alarm_action_type_code.dart';
import 'package:rolling_alarm/enums/routine_ui_phase.dart';
import 'package:rolling_alarm/navigation/routes.dart';
import 'package:rolling_alarm/pages/alarm_ring.dart';
import 'package:rolling_alarm/pages/routine_edit.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
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
    final chrome = _chromeFor(phase);

    return AnimatedContainer(
      duration: RA_ShapeStyles.stateTransitionDuration,
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: RA_ShapeStyles.space16),
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
                        ),
                      )
                    : RA_Routes.fade(
                        RoutineEditPage(
                          dbPath: dbPath,
                          existingRoutine: routine,
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
                const SizedBox(height: RA_ShapeStyles.space16),
                _RoutineCardStatus(routineId: routine.Id),
                const SizedBox(height: RA_ShapeStyles.space16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    RA_IconTextButton(
                      icon: Icons.skip_next,
                      label: 'Dismiss upcoming',
                      onTap: () => unawaited(_handleSkip(ref)),
                    ),
                    const SizedBox(width: RA_ShapeStyles.space8),
                    RA_IconTextButton(
                      icon: Icons.delete_outline,
                      label: 'Delete',
                      color: RA_ColourStyles.softCoral,
                      onTap: () => unawaited(_handleDelete(context, ref)),
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

  Future<void> _handleSkip(WidgetRef ref) async {
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
      );
    });
  }

  Future<void> _handleDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await RA_showDeleteRoutineDialog(
      context,
      routineName: routine.Name,
    );
    if (confirmed != true) return;

    await RA_tryAsync(() async {
      final db = ref.read(RA_DatabaseProvider);
      await RA_AlarmService.cancel(routine.Id);
      await db.softDeleteRoutine(routine.Id);
    });
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
          fill: RA_ColourStyles.surface,
          border: RA_ShapeStyles.idleSurfaceBorder,
          borderWidth: 1,
          glow: null,
          splash: RA_ColourStyles.secondary.withValues(alpha: 0.14),
          highlight: RA_ColourStyles.secondary.withValues(alpha: 0.06),
        ),
    };

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
