import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/components/common/async_list_body.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/page_scaffold.dart';
import 'package:rolling_alarm/components/common/press_scale.dart';
import 'package:rolling_alarm/components/common/status_message.dart';
import 'package:rolling_alarm/components/routine/quick_templates_strip.dart';
import 'package:rolling_alarm/components/routine/routine_card.dart';
import 'package:rolling_alarm/enums/app_theme_mode.dart';
import 'package:rolling_alarm/models/routine_template.dart';
import 'package:rolling_alarm/navigation/routes.dart';
import 'package:rolling_alarm/pages/logs.dart';
import 'package:rolling_alarm/pages/paywall.dart';
import 'package:rolling_alarm/pages/routine_edit.dart';
import 'package:rolling_alarm/pages/settings.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/purchase.dart';
import 'package:rolling_alarm/styles.dart';

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

/// Isolated list body: only this subtree rebuilds on [RoutineListProvider].
class _HomeRoutineList extends ConsumerWidget {
  final String dbPath;

  const _HomeRoutineList({required this.dbPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(AppThemeModeProvider);
    final routinesAsync = ref.watch(RoutineListProvider);

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
              ],
            ),
          ),
        ),
      ),
      errorTitle: 'Could Not Load Routines',
      onRetry: () => ref.invalidate(RoutineListProvider),
      listBuilder: (routines) => ListView.builder(
        padding: RA_ShapeStyles.bodyPaddingWithFab,
        itemCount: routines.length,
        itemBuilder: (_, idx) {
          final routine = routines[idx];
          return RA_RoutineCard(
            key: ValueKey(routine.Id),
            routine: routine,
            dbPath: dbPath,
          );
        },
      ),
    );
  }
}
