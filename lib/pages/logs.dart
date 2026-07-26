import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/components/common/async_list_body.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/components/common/fade_switcher.dart';
import 'package:rolling_alarm/components/common/fitted_text.dart';
import 'package:rolling_alarm/components/common/page_scaffold.dart';
import 'package:rolling_alarm/components/common/status_message.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/log_action_type_code.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/pdf.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:rolling_alarm/utils.dart';

class LogsPage extends StatelessWidget {
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context) {
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
    final logsAsync = ref.watch(LogEntriesProvider(null));

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
        itemBuilder: (_, index) => _LogEntryTile(entry: entries[index]),
      ),
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  final LogEntryModel entry;

  const _LogEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final action = RA_logActionFromCode(entry.LogActionTypeCode);
    final actionColor = action?.color ?? RA_ColourStyles.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: RA_ShapeStyles.space8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: RA_ColourStyles.surface,
          borderRadius: RA_ShapeStyles.largeBorderRadius,
          border: Border.all(
            color: actionColor.withValues(alpha: 0.22),
            width: 1,
          ),
          boxShadow: action?.tileGlow,
        ),
        child: Padding(
          padding: const EdgeInsets.all(RA_ShapeStyles.space16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: RA_ShapeStyles.minTouchTarget + RA_ShapeStyles.space16,
            ),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: actionColor,
                    borderRadius: RA_ShapeStyles.microBorderRadius,
                    boxShadow: [
                      BoxShadow(
                        color: actionColor.withValues(alpha: 0.45),
                        blurRadius: 10,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: const SizedBox(
                    width: RA_ShapeStyles.space8,
                    height: RA_ShapeStyles.minTouchTarget,
                  ),
                ),
                const SizedBox(width: RA_ShapeStyles.space16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action?.name ?? 'Unknown',
                        style: RA_TextStyles.smallFont.copyWith(color: actionColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: RA_ShapeStyles.space8),
                      RA_FittedText(
                        RA_Utils.formatDateTime(entry.Timestamp),
                        style: RA_TextStyles.timestampFont,
                      ),
                    ],
                  ),
                ),
                if (entry.TimeSinceLastDismissalSeconds != null) ...[
                  const SizedBox(width: RA_ShapeStyles.space8),
                  RA_FittedText(
                    RA_Utils.formatSecondsAsDuration(
                      entry.TimeSinceLastDismissalSeconds!,
                    ),
                    style: RA_TextStyles.intervalDigitsFont,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
