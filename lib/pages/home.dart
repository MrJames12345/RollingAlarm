import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/components/common/async_list_body.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/page_scaffold.dart';
import 'package:rolling_alarm/components/common/press_scale.dart';
import 'package:rolling_alarm/components/common/status_message.dart';
import 'package:rolling_alarm/components/routine/routine_card.dart';
import 'package:rolling_alarm/navigation/routes.dart';
import 'package:rolling_alarm/pages/logs.dart';
import 'package:rolling_alarm/pages/routine_edit.dart';
import 'package:rolling_alarm/pages/settings.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/styles.dart';

class HomePage extends StatelessWidget {
  final String dbPath;

  const HomePage({super.key, required this.dbPath});

  @override
  Widget build(BuildContext context) {
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
              Navigator.push(context, RA_Routes.fade(const LogsPage())),
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
            foregroundColor: RA_ColourStyles.offBlack,
            elevation: 0,
            highlightElevation: 0,
            splashColor: RA_ColourStyles.primary.withValues(alpha: 0.22),
            onPressed: () {
              RA_Haptics.heavyUnawaited();
              unawaited(
                Navigator.push(
                  context,
                  RA_Routes.fade(RoutineEditPage(dbPath: dbPath)),
                ),
              );
            },
            child: const Icon(Icons.add, size: 28),
          ),
        ),
      ),
    );
  }
}

/// Isolated list body: only this subtree rebuilds on [RoutineListProvider].
class _HomeRoutineList extends ConsumerWidget {
  final String dbPath;

  const _HomeRoutineList({required this.dbPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routinesAsync = ref.watch(RoutineListProvider);

    return RA_AsyncListBody(
      async: routinesAsync,
      empty: const RA_StatusMessage(
        icon: Icons.alarm_add,
        title: 'No Routines Yet',
        message: 'Tap + below to create your first automated alarm routine.',
      ),
      errorTitle: 'Could Not Load Routines',
      onRetry: () => ref.invalidate(RoutineListProvider),
      listBuilder: (routines) => ListView.builder(
        padding: RA_ShapeStyles.bodyPaddingWithFab,
        itemCount: routines.length,
        itemBuilder: (_, idx) =>
            RA_RoutineCard(routine: routines[idx], dbPath: dbPath),
      ),
    );
  }
}
