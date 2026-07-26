import 'package:flutter/material.dart';
import 'package:rolling_alarm/components/common/async_list_body.dart';
import 'package:rolling_alarm/components/common/log_entry_tile.dart';
import 'package:rolling_alarm/components/common/status_message.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Alarm history for a single routine.
class RA_RoutineHistoryList extends ConsumerWidget {
  final int routineId;

  const RA_RoutineHistoryList({super.key, required this.routineId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(LogEntriesProvider(routineId));

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
        itemBuilder: (_, index) => RA_LogEntryTile(entry: entries[index]),
      ),
    );
  }
}
