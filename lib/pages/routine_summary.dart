import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/components/common/form_section.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/page_scaffold.dart';
import 'package:rolling_alarm/components/common/reset_today_counter_dialog.dart';
import 'package:rolling_alarm/components/common/status_message.dart';
import 'package:rolling_alarm/components/routine/routine_history_list.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';
import 'package:rolling_alarm/models/alarm_sound.dart';
import 'package:rolling_alarm/navigation/routes.dart';
import 'package:rolling_alarm/pages/routine_edit.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/daily_ring_limit.dart';
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
                  _SummaryTab(routine: routine),
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

  const _SummaryTab({required this.routine});

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

    return ListView(
      padding: RA_ShapeStyles.bodyPadding,
      children: [
        RA_FormSection(
          label: 'Alarm sound',
          child: Column(
            children: [
              _SummaryRow(label: 'Sound', value: sound.displayLabel),
              const SizedBox(height: RA_ShapeStyles.space8),
              _SummaryRow(
                label: 'Vibrate',
                value: routine.Vibrate ? 'On' : 'Off',
              ),
            ],
          ),
        ),
        RA_FormSection(
          label: 'Timing',
          child: Column(
            children: [
              _SummaryRow(
                label: 'Interval',
                value: RA_Utils.formatInterval(routine.IntervalSeconds),
              ),
              const SizedBox(height: RA_ShapeStyles.space8),
              _SummaryRow(
                label: 'Snooze',
                value: RA_Utils.formatInterval(routine.SnoozeSeconds),
              ),
              const SizedBox(height: RA_ShapeStyles.space8),
              _SummaryRow(
                label: 'Drift compensation',
                value: compensationLabel,
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
              _SummaryRow(
                label: 'Max times in a day',
                value: routine.MaxTimesPerDayEnabled ? 'On' : 'Off',
              ),
              if (routine.MaxTimesPerDayEnabled) ...[
                const SizedBox(height: RA_ShapeStyles.space8),
                _SummaryRow(label: 'Limit', value: '${routine.MaxTimesPerDay}'),
                const SizedBox(height: RA_ShapeStyles.space8),
                _SummaryRow(label: 'Starts at', value: dayStartLabel),
              ],
              const SizedBox(height: RA_ShapeStyles.space8),
              _SummaryRow(
                label: 'Today',
                value: todayCount == 1 ? '1 time' : '$todayCount times',
              ),
              const SizedBox(height: RA_ShapeStyles.space16),
              RA_Button(
                text: "Reset today's counter",
                isPrimary: false,
                onClick: () => unawaited(_resetTodayCounter(context, ref)),
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
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: RA_ShapeStyles.elevatedSurface(),
      child: Padding(
        padding: const EdgeInsets.all(RA_ShapeStyles.space16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: RA_TextStyles.tinyFont.copyWith(
                  color: RA_ColourStyles.mutedPrimary,
                ),
              ),
            ),
            const SizedBox(width: RA_ShapeStyles.space16),
            Flexible(
              child: Text(
                value,
                style: RA_TextStyles.smallFont.copyWith(
                  color: RA_ColourStyles.secondary,
                ),
                textAlign: TextAlign.end,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
