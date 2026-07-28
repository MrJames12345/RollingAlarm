import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/components/common/async_list_body.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/components/common/fade_switcher.dart';
import 'package:rolling_alarm/components/common/log_entry_tile.dart';
import 'package:rolling_alarm/components/common/page_scaffold.dart';
import 'package:rolling_alarm/components/common/status_message.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/pdf.dart';
import 'package:rolling_alarm/styles.dart';

class LogsPage extends ConsumerWidget {
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(AppThemeModeProvider);
    // AppBar chrome is static; share action and list body watch independently
    // so list insertions do not rebuild the whole scaffold.
    return RA_PageScaffold(
      title: 'Alarm Logs',
      actions: const [_LogsShareAction()],
      body: const _LogsListBody(),
    );
  }
}

/// Share only appears when logs exist; rebuilds only when emptiness flips.
class _LogsShareAction extends ConsumerWidget {
  const _LogsShareAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasLogs = ref.watch(
      LogEntriesProvider(null).select(
        (async) => async.valueOrNull?.isNotEmpty == true,
      ),
    );

    return RA_FadeSwitcher(
      duration: RA_ShapeStyles.stateTransitionDuration,
      child: hasLogs
          ? RA_Keyed(
              'share',
              RA_AppBarIconButton(
                icon: Icons.share,
                tooltip: 'Share PDF Report',
                onPressed: () {
                  final logs = ref.read(LogEntriesProvider(null)).valueOrNull;
                  if (logs == null || logs.isEmpty) return;
                  unawaited(RA_PdfService.shareLogsPdf(logs));
                },
              ),
            )
          : const SizedBox.shrink(key: ValueKey('no-share')),
    );
  }
}

class _LogsListBody extends ConsumerWidget {
  const _LogsListBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(AppThemeModeProvider);
    final logsAsync = ref.watch(LogEntriesProvider(null));
    final nameById =
        ref.watch(RoutineNamesByIdProvider).valueOrNull ?? const {};

    return RA_AsyncListBody(
      async: logsAsync,
      empty: const RA_StatusMessage(
        icon: Icons.history_toggle_off,
        title: 'No Log Entries Yet',
        message:
            'Alarm events like snoozing, skipping, and dismissing will appear here.',
      ),
      errorTitle: 'Could Not Load Logs',
      onRetry: () => ref.invalidate(LogEntriesProvider(null)),
      listBuilder: (entries) => ListView.builder(
        padding: RA_ShapeStyles.bodyPadding,
        itemCount: entries.length,
        itemBuilder: (_, index) {
          final entry = entries[index];
          return RA_LogEntryTile(
            entry: entry,
            routineName: nameById[entry.RoutineId],
          );
        },
      ),
    );
  }
}
