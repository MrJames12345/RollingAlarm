import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/components/common/delete_routine_dialog.dart';
import 'package:rolling_alarm/components/common/fitted_text.dart';
import 'package:rolling_alarm/components/common/form_section.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/page_scaffold.dart';
import 'package:rolling_alarm/components/common/press_scale.dart';
import 'package:rolling_alarm/components/common/reset_today_counter_dialog.dart';
import 'package:rolling_alarm/components/common/status_message.dart';
import 'package:rolling_alarm/components/routine/routine_history_list.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';
import 'package:rolling_alarm/enums/routine_edit_field.dart';
import 'package:rolling_alarm/models/alarm_sound.dart';
import 'package:rolling_alarm/navigation/routes.dart';
import 'package:rolling_alarm/pages/alarm_ring.dart';
import 'package:rolling_alarm/pages/routine_edit.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/daily_ring_limit.dart';
import 'package:rolling_alarm/services/weekday_schedule.dart';
import 'package:rolling_alarm/services/widget.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:rolling_alarm/utils.dart';

/// Read-only overview of a routine with a history tab.
class RoutineSummaryPage extends ConsumerWidget {
  final int routineId;
  final String dbPath;

  const RoutineSummaryPage({
    super.key,
    required this.routineId,
    required this.dbPath,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routine = ref.watch(
      RoutineListProvider.select((async) {
        final list = async.valueOrNull;
        if (list == null) return null;
        for (final item in list) {
          if (item.Id == routineId) return item;
        }
        return null;
      }),
    );

    if (routine == null) {
      return RA_PageScaffold(
        title: 'Routine',
        leading: RA_AppBarIconButton(
          icon: Icons.arrow_back,
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        body: const RA_StatusMessage(
          icon: Icons.alarm_off,
          title: 'Routine unavailable',
          message: 'This routine may have been deleted.',
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: RA_PageScaffold(
        title: routine.Name,
        leading: RA_AppBarIconButton(
          icon: Icons.arrow_back,
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          RA_AppBarIconButton(
            icon: Icons.edit,
            tooltip: 'Edit routine',
            onPressed: () {
              unawaited(
                Navigator.push(
                  context,
                  RA_Routes.fade(
                    RoutineEditPage(dbPath: dbPath, existingRoutine: routine),
                  ),
                ),
              );
            },
          ),
        ],
        body: Column(
          children: [
            Material(
              color: RA_ColourStyles.offBlack,
              child: TabBar(
                labelColor: RA_ColourStyles.secondary,
                unselectedLabelColor: RA_ColourStyles.mutedPrimary,
                labelStyle: RA_TextStyles.smallFont.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: RA_TextStyles.smallFont,
                indicatorColor: RA_ColourStyles.secondary,
                indicatorSize: TabBarIndicatorSize.label,
                dividerColor: RA_ColourStyles.surface,
                tabs: const [
                  Tab(text: 'Summary'),
                  Tab(text: 'History'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _SummaryTab(routine: routine, dbPath: dbPath),
                  RA_RoutineHistoryList(routineId: routine.Id),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryTab extends ConsumerWidget {
  final RoutineModel routine;
  final String dbPath;

  const _SummaryTab({required this.routine, required this.dbPath});

  void _openEdit(BuildContext context, RoutineEditFieldEnum field) {
    RA_Haptics.heavyUnawaited();
    unawaited(
      Navigator.push(
        context,
        RA_Routes.fade(
          RoutineEditPage(
            dbPath: dbPath,
            existingRoutine: routine,
            scrollToField: field,
          ),
        ),
      ),
    );
  }

  /// Opens the real alarm UI with this routine's sound settings; snooze/dismiss
  /// only pop.
  Future<void> _previewAlarm(BuildContext context) async {
    final sound = RA_AlarmSound.decode(routine.AudioUri);
    await Navigator.of(context).push<void>(
      RA_Routes.alarmRing(
        AlarmRingPage(
          routineId: 0,
          routineName: routine.Name,
          audioUri: routine.AudioUri,
          vibrate: routine.Vibrate,
          volume: routine.Volume,
          fadeIn: sound.isSilent ? false : routine.FadeIn,
          isPreview: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sound = RA_AlarmSound.decode(routine.AudioUri);
    final compensationIndex = routine.DriftCompensationTypeCode;
    final compensation =
        compensationIndex >= 0 &&
            compensationIndex < DriftCompensationTypeCodeEnum.values.length
        ? DriftCompensationTypeCodeEnum.values[compensationIndex]
        : DriftCompensationTypeCodeEnum.ActualDismissal;
    final compensationLabel = switch (compensation) {
      DriftCompensationTypeCodeEnum.InitialRing => 'Classic Interval',
      DriftCompensationTypeCodeEnum.ActualDismissal => 'Actual Dismissal',
    };

    final dayStart = RA_DailyRingLimit.normalizeDayStartSeconds(
      routine.DayStartSeconds,
    );
    final dayStartLabel = RA_Utils.formatTime(
      DateTime(2000, 1, 1).add(Duration(seconds: dayStart)),
    );

    final todayCount = ref.watch(
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

    final dailyLimitTiles = <Widget>[
      _SummaryTile(
        label: 'Max times in a day',
        value: routine.MaxTimesPerDayEnabled ? 'On' : 'Off',
        onTap: () => _openEdit(context, RoutineEditFieldEnum.maxTimesPerDay),
      ),
      if (routine.MaxTimesPerDayEnabled) ...[
        _SummaryTile(
          label: 'Limit',
          value: '${routine.MaxTimesPerDay}',
          onTap: () => _openEdit(context, RoutineEditFieldEnum.maxTimesLimit),
        ),
        _SummaryTile(
          label: 'Starts at',
          value: dayStartLabel,
          onTap: () => _openEdit(context, RoutineEditFieldEnum.dayStart),
        ),
      ],
      _SummaryTile(
        label: 'Today',
        value: todayCount == 1 ? '1 time' : '$todayCount times',
      ),
    ];

    return ListView(
      padding: RA_ShapeStyles.bodyPadding,
      children: [
        RA_FormSection(
          label: 'Alarm sound',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SummaryTileRow(
                children: [
                  _SummaryTile(
                    label: 'Sound',
                    value: sound.displayLabel,
                    onTap: () => _openEdit(context, RoutineEditFieldEnum.sound),
                  ),
                  _SummaryTile(
                    label: 'Volume',
                    value: sound.isSilent
                        ? 'N/A'
                        : '${routine.Volume.clamp(5, 100)}%',
                    onTap: () =>
                        _openEdit(context, RoutineEditFieldEnum.volume),
                  ),
                  _SummaryTile(
                    label: 'Fade in',
                    value: sound.isSilent
                        ? 'N/A'
                        : (routine.FadeIn ? 'On' : 'Off'),
                    onTap: () =>
                        _openEdit(context, RoutineEditFieldEnum.fadeIn),
                  ),
                  _SummaryTile(
                    label: 'Vibrate',
                    value: routine.Vibrate ? 'On' : 'Off',
                    onTap: () =>
                        _openEdit(context, RoutineEditFieldEnum.vibrate),
                  ),
                ],
              ),
              const SizedBox(height: RA_ShapeStyles.space16),
              RA_Button(
                text: 'Preview',
                isPrimary: false,
                onClick: () => unawaited(_previewAlarm(context)),
              ),
            ],
          ),
        ),
        RA_FormSection(
          label: 'Timing',
          child: _SummaryTileRow(
            flexes: const [2, 2, 2, 2],
            children: [
              _SummaryTile(
                label: 'Interval',
                value: RA_Utils.formatInterval(routine.IntervalSeconds),
                onTap: () => _openEdit(context, RoutineEditFieldEnum.interval),
              ),
              _SummaryTile(
                label: 'Snooze',
                value: RA_Utils.formatInterval(routine.SnoozeSeconds),
                onTap: () => _openEdit(context, RoutineEditFieldEnum.snooze),
              ),
              _SummaryTile(
                label: 'Days',
                value: RA_WeekdaySchedule.summaryLabel(routine.EnabledWeekdays),
                onTap: () => _openEdit(context, RoutineEditFieldEnum.days),
              ),
              _SummaryTile(
                label: 'Drift compensation',
                value: compensationLabel,
                onTap: () =>
                    _openEdit(context, RoutineEditFieldEnum.driftCompensation),
              ),
            ],
          ),
        ),
        RA_FormSection(
          label: 'Daily limit',
          bottomSpacing: RA_ShapeStyles.space48,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SummaryTileRow(children: dailyLimitTiles),
              const SizedBox(height: RA_ShapeStyles.space16),
              RA_Button(
                text: "Reset Today's Counter",
                isPrimary: false,
                onClick: () => unawaited(_resetTodayCounter(context, ref)),
              ),
              const SizedBox(height: RA_ShapeStyles.space16),
              RA_Button(
                text: 'Delete',
                backgroundColor: RA_ColourStyles.softCoral,
                foregroundColor: RA_ColourStyles.onAccent,
                shadowColor: RA_ColourStyles.softCoral.withValues(alpha: 0.35),
                onClick: () => unawaited(_deleteRoutine(context, ref)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _resetTodayCounter(BuildContext context, WidgetRef ref) async {
    final confirmed = await RA_showResetTodayCounterDialog(context);
    if (confirmed != true) return;

    RA_Haptics.heavyUnawaited();
    final db = ref.read(RA_DatabaseProvider);
    final now = DateTime.now();
    final period = RA_DailyRingLimit.periodStart(now, routine.DayStartSeconds);
    await db.updateRoutineState(
      routine.Id,
      RoutineStatesCompanion(
        TimesRingToday: const Value(0),
        TimesRingDay: Value(period),
      ),
    );
  }

  /// Same confirm + soft-delete path as a Delete swipe on the home routine tile.
  Future<void> _deleteRoutine(BuildContext context, WidgetRef ref) async {
    final confirmed = await RA_showDeleteRoutineDialog(
      context,
      routineName: routine.Name,
    );
    if (confirmed != true) return;

    final deleted = await RA_tryAsync(() async {
      final db = ref.read(RA_DatabaseProvider);
      await RA_AlarmService.cancel(routine.Id);
      await db.softDeleteRoutine(routine.Id);
      await RA_WidgetService.updateWidgetState(db: db);
      return true;
    });
    if (deleted == true && context.mounted) {
      Navigator.pop(context);
    }
  }
}

/// Equal-height tiles in one horizontal row for a summary section.
class _SummaryTileRow extends StatelessWidget {
  final List<Widget> children;
  final List<int>? flexes;

  const _SummaryTileRow({required this.children, this.flexes});

  @override
  Widget build(BuildContext context) {
    assert(
      flexes == null || flexes!.length == children.length,
      'flexes length must match children length',
    );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: RA_ShapeStyles.space8),
            Expanded(flex: flexes?[i] ?? 1, child: children[i]),
          ],
        ],
      ),
    );
  }
}

/// Compact summary cell: muted label over value, centered.
class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _SummaryTile({required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(RA_ShapeStyles.space8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RA_FittedText(
            label,
            alignment: Alignment.center,
            style: RA_TextStyles.tinyFont.copyWith(
              color: RA_ColourStyles.mutedPrimary,
            ),
          ),
          const SizedBox(height: RA_ShapeStyles.space8),
          RA_FittedText(
            value,
            alignment: Alignment.center,
            style: RA_TextStyles.smallFont.copyWith(
              color: RA_ColourStyles.valueText,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return DecoratedBox(
        decoration: RA_ShapeStyles.elevatedSurface(),
        child: content,
      );
    }

    return RA_PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: RA_ShapeStyles.largeBorderRadius,
          splashColor: RA_ColourStyles.secondary.withValues(alpha: 0.16),
          highlightColor: RA_ColourStyles.secondary.withValues(alpha: 0.08),
          child: Ink(
            decoration: RA_ShapeStyles.elevatedSurface(),
            child: content,
          ),
        ),
      ),
    );
  }
}
