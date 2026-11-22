import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/components/common/async_list_body.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/components/common/fade_switcher.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/log_entry_tile.dart';
import 'package:rolling_alarm/components/common/page_scaffold.dart';
import 'package:rolling_alarm/components/common/press_scale.dart';
import 'package:rolling_alarm/components/common/pro_badge.dart';
import 'package:rolling_alarm/components/common/recover_routine_dialog.dart';
import 'package:rolling_alarm/components/common/status_message.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/log_action_type_code.dart';
import 'package:rolling_alarm/pages/paywall.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/pdf.dart';
import 'package:rolling_alarm/services/permissions.dart';
import 'package:rolling_alarm/services/purchase.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:rolling_alarm/utils.dart';

class LogsPage extends ConsumerWidget {
  final String dbPath;

  const LogsPage({super.key, required this.dbPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(AppThemeModeProvider);
    // AppBar chrome is static; share action and list body watch independently
    // so list insertions do not rebuild the whole scaffold.
    return RA_PageScaffold(
      title: 'Alarm Logs',
      actions: const [_LogsShareAction()],
      body: _LogsListBody(dbPath: dbPath),
    );
  }
}

/// Share only appears when logs exist; rebuilds only when emptiness flips.
class _LogsShareAction extends ConsumerWidget {
  const _LogsShareAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(IsProProvider);
    final hasLogs = ref.watch(
      LogEntriesProvider(null).select(
        (async) => async.valueOrNull?.isNotEmpty == true,
      ),
    );

    return RA_FadeSwitcher(
      duration: RA_ShapeStyles.stateTransitionDuration,
      child: hasLogs
          ? RA_Keyed(
              'share_${isPro ? 'pro' : 'free'}',
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isPro)
                    GestureDetector(
                      onTap: () {
                        RA_Haptics.heavyUnawaited();
                        unawaited(_shareLogs(context, ref));
                      },
                      child: const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: RA_ProBadge(),
                      ),
                    ),
                  RA_AppBarIconButton(
                    icon: Icons.share,
                    tooltip: 'Share PDF Report',
                    onPressed: () => unawaited(_shareLogs(context, ref)),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(key: ValueKey('no-share')),
    );
  }

  Future<void> _shareLogs(BuildContext context, WidgetRef ref) async {
    if (!ref.read(IsProProvider)) {
      final unlocked = await PaywallPage.show(
        context,
        featureTrigger: 'Export printable PDF adherence logs with Pro',
      );
      if (!unlocked || !context.mounted) return;
    }

    await RA_tryAsync(() async {
      final db = ref.read(RA_DatabaseProvider);
      final logs = await db.getLogEntriesForExport(
        limit: RA_PdfService.maxExportRows,
      );
      if (logs.isEmpty) return;
      final cachedNames = ref.read(RoutineNamesByIdProvider).valueOrNull;
      final routineNamesById =
          cachedNames ?? await db.watchRoutineNamesById().first;
      await RA_PdfService.shareLogsPdf(
        logs,
        routineNamesById: routineNamesById,
      );
    });
  }
}

class _LogsListBody extends ConsumerStatefulWidget {
  final String dbPath;

  const _LogsListBody({required this.dbPath});

  @override
  ConsumerState<_LogsListBody> createState() => _LogsListBodyState();
}

class _LogsListBodyState extends ConsumerState<_LogsListBody>
    with WidgetsBindingObserver {
  static const int _pageSize = 250;
  int _limit = _pageSize;

  /// Floored to the minute and refreshed on resume so the 7-day Free cutoff
  /// does not churn the Riverpod family key on rebuilds while staying accurate
  /// across multi-day background sessions.
  late DateTime _freeCutoff = _computeFreeCutoff();

  static DateTime _computeFreeCutoff() {
    final raw = DateTime.now().subtract(
      const Duration(days: RA_PurchaseService.freeLogHistoryDays),
    );
    return DateTime(raw.year, raw.month, raw.day, raw.hour, raw.minute);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final next = _computeFreeCutoff();
      if (next != _freeCutoff) {
        setState(() => _freeCutoff = next);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(AppThemeModeProvider);
    final isPro = ref.watch(IsProProvider);
    final queryArgs = (
      routineId: null,
      limit: _limit,
      since: isPro ? null : _freeCutoff,
    );
    final logsAsync = ref.watch(PagedLogEntriesProvider(queryArgs));
    final nameById =
        ref.watch(RoutineNamesByIdProvider).valueOrNull ?? const {};
    final deletedById =
        ref.watch(RoutineDeletedByIdProvider).valueOrNull ?? const {};

    return RA_AsyncListBody(
      async: logsAsync,
      empty: isPro
          ? const RA_StatusMessage(
              icon: Icons.history_toggle_off,
              title: 'No Log Entries Yet',
              message:
                  'Alarm events like snoozing, skipping, and dismissing will appear here.',
            )
          : LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(height: RA_ShapeStyles.space16),
                      const RA_StatusMessage(
                        icon: Icons.history_toggle_off,
                        title: 'No Recent Log Entries',
                        message:
                            'Free shows the last 7 days of alarm events. Upgrade to Pro for full 365-day history.',
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          RA_ShapeStyles.space16,
                          0,
                          RA_ShapeStyles.space16,
                          RA_ShapeStyles.space24,
                        ),
                        child: _LogsProUpgradeCard(
                          onTap: () => unawaited(
                            PaywallPage.show(
                              context,
                              featureTrigger:
                                  'Unlock full 365-day adherence log history with Pro',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      errorTitle: 'Could Not Load Logs',
      onRetry: () => ref.invalidate(PagedLogEntriesProvider(queryArgs)),
      listBuilder: (entries) {
        final hasMore = entries.length >= _limit;
        final extraFooterCount = (hasMore ? 1 : 0) + (!isPro ? 1 : 0);
        return ListView.builder(
          padding: RA_ShapeStyles.bodyPadding,
          itemCount: entries.length + extraFooterCount,
          itemBuilder: (_, index) {
            if (index >= entries.length) {
              final footerOffset = index - entries.length;
              if (hasMore && footerOffset == 0) {
                return Padding(
                  padding: EdgeInsets.only(
                    top: RA_ShapeStyles.space8,
                    bottom: isPro
                        ? RA_ShapeStyles.space24
                        : RA_ShapeStyles.space8,
                  ),
                  child: RA_Button(
                    text: 'Load older logs',
                    isPrimary: false,
                    onClick: () => setState(() => _limit += _pageSize),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(
                  top: RA_ShapeStyles.space8,
                  bottom: RA_ShapeStyles.space24,
                ),
                child: _LogsProUpgradeCard(
                  onTap: () => unawaited(
                    PaywallPage.show(
                      context,
                      featureTrigger:
                          'Unlock full 365-day adherence log history with Pro',
                    ),
                  ),
                ),
              );
            }
            final entry = entries[index];
            final isDelete =
                entry.LogActionTypeCode == LogActionTypeCodeEnum.Delete.index;
            final isSoftDeleted = deletedById[entry.RoutineId] == true;
            return RA_LogEntryTile(
              entry: entry,
              routineName: nameById[entry.RoutineId],
              showRecover: isDelete && isSoftDeleted,
              onRecover: isDelete && isSoftDeleted
                  ? () => unawaited(
                      _recoverFromLog(
                        context,
                        ref,
                        entry: entry,
                        routineName: nameById[entry.RoutineId],
                        dbPath: widget.dbPath,
                      ),
                    )
                  : null,
            );
          },
        );
      },
    );
  }
}

class _LogsProUpgradeCard extends StatelessWidget {
  final VoidCallback onTap;

  const _LogsProUpgradeCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return RA_PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            RA_Haptics.heavyUnawaited();
            onTap();
          },
          borderRadius: RA_ShapeStyles.largeBorderRadius,
          splashColor: RA_ColourStyles.secondary.withValues(alpha: 0.16),
          highlightColor: RA_ColourStyles.secondary.withValues(alpha: 0.08),
          child: Ink(
            decoration: RA_ShapeStyles.elevatedSurface(
              borderColor: RA_ColourStyles.secondary.withValues(alpha: 0.45),
              borderWidth: 1.5,
              boxShadow: RA_ShapeStyles.tealGlow,
            ),
            child: Padding(
              padding: const EdgeInsets.all(RA_ShapeStyles.space16),
              child: Row(
                children: [
                  const Icon(
                    Icons.history_rounded,
                    color: RA_ColourStyles.secondary,
                  ),
                  const SizedBox(width: RA_ShapeStyles.space16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Showing last 7 days',
                                style: RA_TextStyles.smallFont.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const RA_ProBadge(),
                          ],
                        ),
                        const SizedBox(height: RA_ShapeStyles.space8),
                        Text(
                          'Unlock full 365-day log history & printable PDF adherence reports with Rolling Alarm Pro.',
                          style: RA_TextStyles.tinyFont.copyWith(
                            color: RA_ColourStyles.mutedPrimary,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _recoverFromLog(
  BuildContext context,
  WidgetRef ref, {
  required LogEntryModel entry,
  required String? routineName,
  required String dbPath,
}) async {
  if (!ref.read(IsProProvider)) {
    final liveCount = await ref.read(RA_DatabaseProvider).countLiveRoutines();
    if (!context.mounted) return;
    if (liveCount >= RA_PurchaseService.freeRoutineLimit) {
      final unlocked = await PaywallPage.show(
        context,
        featureTrigger: 'Create unlimited rolling routines with Pro',
      );
      if (!unlocked || !context.mounted) return;
    }
  }

  final name = (routineName != null && routineName.trim().isNotEmpty)
      ? routineName.trim()
      : 'this routine';
  final confirmed = await RA_showRecoverRoutineDialog(
    context,
    routineName: name,
  );
  if (confirmed != true) return;

  final recovered = await RA_tryAsync(() async {
    final db = ref.read(RA_DatabaseProvider);
    return RA_AlarmService.recoverRoutine(
      routineId: entry.RoutineId,
      db: db,
      dbPath: dbPath,
    );
  });
  if (recovered == true && context.mounted) {
    await RA_PermissionService.ensureCoreAlarmPermissions(context);
  }
}
