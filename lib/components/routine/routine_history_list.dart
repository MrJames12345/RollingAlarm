import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/components/common/async_list_body.dart';
import 'package:rolling_alarm/components/common/log_entry_tile.dart';
import 'package:rolling_alarm/components/common/recover_routine_dialog.dart';
import 'package:rolling_alarm/components/common/status_message.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/log_action_type_code.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:rolling_alarm/utils.dart';

/// Alarm history for a single routine.
class RA_RoutineHistoryList extends ConsumerWidget {
  final int routineId;
  final String dbPath;
  final String routineName;

  const RA_RoutineHistoryList({
    super.key,
    required this.routineId,
    required this.dbPath,
    required this.routineName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(LogEntriesProvider(routineId));
    final deletedById =
        ref.watch(RoutineDeletedByIdProvider).valueOrNull ?? const {};
    final isSoftDeleted = deletedById[routineId] == true;

    return RA_AsyncListBody(
      async: logsAsync,
      empty: const RA_StatusMessage(
        icon: Icons.history_toggle_off,
        title: 'No History Yet',
        message:
            'Alarm events for this routine like snoozing, skipping, and dismissing will appear here.',
      ),
      errorTitle: 'Could Not Load History',
      onRetry: () => ref.invalidate(LogEntriesProvider(routineId)),
      listBuilder: (entries) => ListView.builder(
        padding: RA_ShapeStyles.bodyPadding,
        itemCount: entries.length,
        itemBuilder: (_, index) {
          final entry = entries[index];
          final isDelete =
              entry.LogActionTypeCode == LogActionTypeCodeEnum.Delete.index;
          return RA_LogEntryTile(
            entry: entry,
            showRecover: isDelete && isSoftDeleted,
            onRecover: isDelete && isSoftDeleted
                ? () => unawaited(
                    _recoverFromHistory(
                      context,
                      ref,
                      entry: entry,
                      routineName: routineName,
                      dbPath: dbPath,
                    ),
                  )
                : null,
          );
        },
      ),
    );
  }
}

Future<void> _recoverFromHistory(
  BuildContext context,
  WidgetRef ref, {
  required LogEntryModel entry,
  required String routineName,
  required String dbPath,
}) async {
  final confirmed = await RA_showRecoverRoutineDialog(
    context,
    routineName: routineName,
  );
  if (confirmed != true) return;

  await RA_tryAsync(() async {
    final db = ref.read(RA_DatabaseProvider);
    await RA_AlarmService.recoverRoutine(
      routineId: entry.RoutineId,
      db: db,
      dbPath: dbPath,
    );
  });
}
