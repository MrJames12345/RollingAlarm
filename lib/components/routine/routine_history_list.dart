import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/components/common/async_list_body.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/log_entry_tile.dart';
import 'package:rolling_alarm/components/common/press_scale.dart';
import 'package:rolling_alarm/components/common/pro_badge.dart';
import 'package:rolling_alarm/components/common/recover_routine_dialog.dart';
import 'package:rolling_alarm/components/common/status_message.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/log_action_type_code.dart';
import 'package:rolling_alarm/pages/paywall.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/permissions.dart';
import 'package:rolling_alarm/services/purchase.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:rolling_alarm/utils.dart';

/// Alarm history for a single routine.
///
/// Mirrors [LogsPage] pagination and Free-tier 7-day log window enforcement.
class RA_RoutineHistoryList extends ConsumerStatefulWidget {
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
  ConsumerState<RA_RoutineHistoryList> createState() =>
      _RA_RoutineHistoryListState();
}

class _RA_RoutineHistoryListState extends ConsumerState<RA_RoutineHistoryList>
    with WidgetsBindingObserver {
  static const int _pageSize = 250;
  int _limit = _pageSize;

  /// Floored to the minute and refreshed on resume so the 7-day Free cutoff
  /// does not churn the Riverpod family key on rebuilds.
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
      routineId: widget.routineId,
      limit: _limit,
      since: isPro ? null : _freeCutoff,
    );
    final logsAsync = ref.watch(PagedLogEntriesProvider(queryArgs));
    final deletedById =
        ref.watch(RoutineDeletedByIdProvider).valueOrNull ?? const {};
    final isSoftDeleted = deletedById[widget.routineId] == true;

    return RA_AsyncListBody(
      async: logsAsync,
      empty: isPro
          ? const RA_StatusMessage(
              icon: Icons.history_toggle_off,
              title: 'No History Yet',
              message:
                  'Alarm events for this routine like snoozing, skipping, and dismissing will appear here.',
            )
          : LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(height: RA_ShapeStyles.space16),
                      const RA_StatusMessage(
                        icon: Icons.history_toggle_off,
                        title: 'No Recent History',
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
                        child: _HistoryProUpgradeCard(
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
      errorTitle: 'Could Not Load History',
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
                child: _HistoryProUpgradeCard(
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
            return RA_LogEntryTile(
              entry: entry,
              showRecover: isDelete && isSoftDeleted,
              onRecover: isDelete && isSoftDeleted
                  ? () => unawaited(
                      _recoverFromHistory(
                        context,
                        ref,
                        entry: entry,
                        routineName: widget.routineName,
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

class _HistoryProUpgradeCard extends StatelessWidget {
  final VoidCallback onTap;

  const _HistoryProUpgradeCard({required this.onTap});

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

Future<void> _recoverFromHistory(
  BuildContext context,
  WidgetRef ref, {
  required LogEntryModel entry,
  required String routineName,
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

  final confirmed = await RA_showRecoverRoutineDialog(
    context,
    routineName: routineName,
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
