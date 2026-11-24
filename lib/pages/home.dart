import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/components/common/async_list_body.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/import_export_dialogs.dart';
import 'package:rolling_alarm/components/common/page_scaffold.dart';
import 'package:rolling_alarm/components/common/press_scale.dart';
import 'package:rolling_alarm/components/common/status_message.dart';
import 'package:rolling_alarm/components/routine/quick_templates_strip.dart';
import 'package:rolling_alarm/components/routine/routine_card.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/app_theme_mode.dart';
import 'package:rolling_alarm/models/routine_template.dart';
import 'package:rolling_alarm/navigation/routes.dart';
import 'package:rolling_alarm/pages/logs.dart';
import 'package:rolling_alarm/pages/paywall.dart';
import 'package:rolling_alarm/pages/routine_edit.dart';
import 'package:rolling_alarm/pages/settings.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/export.dart';
import 'package:rolling_alarm/services/permissions.dart';
import 'package:rolling_alarm/services/purchase.dart';
import 'package:rolling_alarm/services/widget.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:rolling_alarm/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends ConsumerWidget {
  final String dbPath;

  const HomePage({super.key, required this.dbPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(AppThemeModeProvider);
    final isLight = RA_ColourStyles.mode == AppThemeModeEnum.Light;
    // Scaffold chrome (AppBar / FAB) stays outside the list consumer so
    // RoutineListProvider emissions never rebuild the whole page shell.
    return RA_PageScaffold(
      title: 'Rolling Alarm',
      actions: [
        RA_AppBarIconButton(
          icon: Icons.settings,
          tooltip: 'Settings',
          onPressed: () {
            unawaited(
              Navigator.push(
                context,
                RA_Routes.fade(SettingsPage(dbPath: dbPath)),
              ),
            );
          },
        ),
        RA_AppBarIconButton(
          icon: Icons.history,
          tooltip: 'Alarm Logs',
          onPressed: () {
            unawaited(
              Navigator.push(
                context,
                RA_Routes.fade(LogsPage(dbPath: dbPath)),
              ),
            );
          },
        ),
      ],
      body: _HomeRoutineList(dbPath: dbPath),
      floatingActionButton: RA_PressScale(
        pressedScale: 0.94,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: RA_ShapeStyles.largeBorderRadius,
            boxShadow: RA_ShapeStyles.tealGlow,
          ),
          child: FloatingActionButton(
            backgroundColor: RA_ColourStyles.secondary,
            foregroundColor: RA_ColourStyles.onAccent,
            elevation: 0,
            highlightElevation: 0,
            // Ink on sage: near-black on light paper, soft white on OLED.
            splashColor: isLight
                ? RA_ColourStyles.onAccent.withValues(alpha: 0.18)
                : RA_ColourStyles.primary.withValues(alpha: 0.22),
            shape: RoundedRectangleBorder(
              borderRadius: RA_ShapeStyles.largeBorderRadius,
              side: isLight
                  ? BorderSide(
                      color: RA_ColourStyles.onAccent.withValues(alpha: 0.14),
                      width: 1,
                    )
                  : BorderSide.none,
            ),
            onPressed: () {
              RA_Haptics.heavyUnawaited();
              unawaited(_openNewRoutine(context, ref, dbPath: dbPath));
            },
            child: const Icon(
              Icons.add,
              size: 28,
              color: RA_ColourStyles.onAccent,
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _openNewRoutine(
  BuildContext context,
  WidgetRef ref, {
  required String dbPath,
  RA_RoutineTemplate? initialTemplate,
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
  await Navigator.push(
    context,
    RA_Routes.fade(
      RoutineEditPage(dbPath: dbPath, initialTemplate: initialTemplate),
    ),
  );
}

Future<void> _importSharedPreset(
  BuildContext context,
  WidgetRef ref, {
  required String dbPath,
}) async {
  var importedCount = 0;
  await RA_showImportDialog(
    context,
    onImport: (text) async {
      final payload = RA_ExportService.decodeExportString(text);
      final rawRoutines = payload['routines'] as List<Object?>;
      final incomingCount = rawRoutines.length;
      final db = ref.read(RA_DatabaseProvider);

      if (!ref.read(IsProProvider) && incomingCount > 0) {
        final existingLiveCount = await db.countLiveRoutines();
        if (existingLiveCount + incomingCount >
            RA_PurchaseService.freeRoutineLimit) {
          if (!context.mounted) return false;
          final unlocked = await PaywallPage.show(
            context,
            featureTrigger: 'Import unlimited routines & backups with Pro',
          );
          if (!unlocked || !context.mounted) return false;
        }
      }

      final importedIds = await RA_ExportService.importFromBase64(db, text);
      importedCount = importedIds.length;
      await _scheduleImportedRoutines(db, importedIds, dbPath: dbPath);
      return true;
    },
  );
  if (importedCount > 0 && context.mounted) {
    await RA_PermissionService.ensureCoreAlarmPermissions(context);
  }
}

Future<void> _scheduleImportedRoutines(
  RA_Database db,
  List<int> routineIds, {
  required String dbPath,
}) async {
  for (final routineId in routineIds) {
    final routine = await db.getRoutineById(routineId);
    if (!routine.IsActive) continue;
    final state = await db.getRoutineState(routineId);
    final next = state?.NextTriggerTime;
    if (next == null) continue;
    await RA_AlarmService.scheduleNext(
      routineId: routineId,
      triggerTime: next,
      dbPath: dbPath,
      routineName: routine.Name,
      routine: routine,
      state: state,
      refreshWidget: false,
    );
  }
  await RA_WidgetService.updateWidgetState(db: db);
}

/// Isolated list body: only this subtree rebuilds on [RoutineListProvider].
class _HomeRoutineList extends ConsumerWidget {
  final String dbPath;

  const _HomeRoutineList({required this.dbPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(AppThemeModeProvider);
    final routinesAsync = ref.watch(RoutineListProvider);
    final isPro = ref.watch(IsProProvider);

    return RA_AsyncListBody(
      async: routinesAsync,
      empty: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.only(
            bottom: RA_ShapeStyles.space48 + RA_ShapeStyles.space48,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  (constraints.maxHeight -
                          (RA_ShapeStyles.space48 + RA_ShapeStyles.space48))
                      .clamp(0.0, double.infinity),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RA_StatusMessage(
                  icon: Icons.alarm_add,
                  title: 'No Routines Yet',
                  message:
                      'Tap a Quick Template below or + to create your first automated alarm routine.',
                  iconSemanticsLabel: 'Add routine',
                  onIconTap: () {
                    RA_Haptics.heavyUnawaited();
                    unawaited(_openNewRoutine(context, ref, dbPath: dbPath));
                  },
                ),
                RA_QuickTemplatesStrip(
                  horizontalPadding: const EdgeInsets.symmetric(
                    horizontal: RA_ShapeStyles.space16,
                  ),
                  onSelect: (template) => unawaited(
                    _openNewRoutine(
                      context,
                      ref,
                      dbPath: dbPath,
                      initialTemplate: template,
                    ),
                  ),
                ),
                const SizedBox(height: RA_ShapeStyles.space16),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RA_ShapeStyles.space16,
                  ),
                  child: RA_DialogButton(
                    'Import Shared Preset',
                    () => unawaited(
                      _importSharedPreset(context, ref, dbPath: dbPath),
                    ),
                    color: RA_ColourStyles.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      errorTitle: 'Could Not Load Routines',
      onRetry: () => ref.invalidate(RoutineListProvider),
      listBuilder: (routines) {
        final showBannerSlot = !isPro && routines.isNotEmpty;
        return ListView.builder(
          padding: RA_ShapeStyles.bodyPaddingWithFab,
          itemCount: routines.length + (showBannerSlot ? 1 : 0),
          itemBuilder: (_, idx) {
            if (showBannerSlot && idx == 0) {
              return const _FoundingOfferBanner();
            }
            final routine = routines[idx - (showBannerSlot ? 1 : 0)];
            return RA_RoutineCard(
              key: ValueKey(routine.Id),
              routine: routine,
              dbPath: dbPath,
            );
          },
        );
      },
    );
  }
}

/// Compact, dismissible Day-1 Founding Offer banner rendered above the routine
/// list for Free users during their first 24 hours.
class _FoundingOfferBanner extends ConsumerStatefulWidget {
  const _FoundingOfferBanner();

  @override
  ConsumerState<_FoundingOfferBanner> createState() =>
      _FoundingOfferBannerState();
}

class _FoundingOfferBannerState extends ConsumerState<_FoundingOfferBanner> {
  bool _foundingBannerDismissed = false;
  bool _hydrated = false;

  @override
  void initState() {
    super.initState();
    unawaited(_hydrate());
  }

  Future<void> _hydrate() async {
    var dismissed = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      dismissed =
          prefs.getBool(RA_PurchaseService.foundingBannerDismissedKey) ?? false;
    } catch (_) {}
    await RA_PurchaseService.foundingOfferRemaining();
    if (!mounted) return;
    setState(() {
      _foundingBannerDismissed = dismissed;
      _hydrated = true;
    });
  }

  Future<void> _dismiss() async {
    setState(() => _foundingBannerDismissed = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(RA_PurchaseService.foundingBannerDismissedKey, true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_hydrated ||
        _foundingBannerDismissed ||
        !RA_PurchaseService.isFoundingOfferActive()) {
      return const SizedBox.shrink();
    }
    final tickNow = ref.watch(WallClockSecondProvider).valueOrNull;
    if (!RA_PurchaseService.isFoundingOfferActive(now: tickNow)) {
      return const SizedBox.shrink();
    }
    final remaining = RA_PurchaseService.foundingOfferRemainingSync(
      now: tickNow,
    );
    final readableCoral = RA_ColourStyles.readableAccent(
      RA_ColourStyles.softCoral,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: RA_ShapeStyles.space16),
      child: RA_PressScale(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              RA_Haptics.heavyUnawaited();
              unawaited(
                PaywallPage.show(
                  context,
                  featureTrigger:
                      'Claim your 24-hour Day-1 Founding Lifetime unlock',
                ),
              );
            },
            borderRadius: RA_ShapeStyles.largeBorderRadius,
            splashColor: RA_ColourStyles.softCoral.withValues(alpha: 0.16),
            highlightColor: RA_ColourStyles.softCoral.withValues(alpha: 0.08),
            child: Ink(
              decoration: RA_ShapeStyles.elevatedSurface(
                fill: Color.alphaBlend(
                  RA_ColourStyles.softCoral.withValues(alpha: 0.09),
                  RA_ColourStyles.surface,
                ),
                borderColor: RA_ColourStyles.softCoral.withValues(alpha: 0.45),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  12,
                  RA_ShapeStyles.space8,
                  4,
                  RA_ShapeStyles.space8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.local_offer_outlined,
                      size: 16,
                      color: readableCoral,
                    ),
                    const SizedBox(width: RA_ShapeStyles.space8),
                    Expanded(
                      child: Text(
                        'Day-1 Founding Offer · Own Lifetime Pro forever (Ends in ${RA_Utils.formatCountdown(remaining)})',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: RA_TextStyles.tinyFont.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: readableCoral,
                          height: 1.3,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: RA_ColourStyles.mutedPrimary,
                      ),
                      tooltip: 'Dismiss offer banner',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        RA_Haptics.heavyUnawaited();
                        unawaited(_dismiss());
                      },
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
}
