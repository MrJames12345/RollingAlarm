import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/components/common/fitted_text.dart';
import 'package:rolling_alarm/components/common/form_section.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/import_export_dialogs.dart';
import 'package:rolling_alarm/components/common/page_scaffold.dart';
import 'package:rolling_alarm/components/common/press_scale.dart';
import 'package:rolling_alarm/components/field/radio_group.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/alarm_side_button_action.dart';
import 'package:rolling_alarm/enums/alarm_snooze_dismiss_layout.dart';
import 'package:rolling_alarm/enums/app_theme_mode.dart';
import 'package:rolling_alarm/enums/routine_swipe_action.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/export.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:rolling_alarm/utils.dart';

class SettingsPage extends ConsumerStatefulWidget {
  final String dbPath;

  const SettingsPage({super.key, required this.dbPath});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final layout =
        ref.watch(AlarmSnoozeDismissLayoutProvider).valueOrNull ??
        AlarmSnoozeDismissLayoutEnum.Sliders;
    final themeMode =
        ref.watch(AppThemeModeProvider).valueOrNull ?? AppThemeModeEnum.Dark;
    final sideButtons =
        ref.watch(AlarmSideButtonsProvider).valueOrNull ??
        const AlarmSideButtonsSettings();
    final swipeActions =
        ref.watch(RoutineSwipeActionsProvider).valueOrNull ??
        const RoutineSwipeActionsSettings();

    return RA_PageScaffold(
      title: 'Settings',
      body: ListView(
        padding: RA_ShapeStyles.bodyPadding,
        children: [
          RA_FormSection(
            label: 'Theme',
            child: RA_RadioGroup<AppThemeModeEnum>(
              groupValue: themeMode,
              onChanged: (v) =>
                  unawaited(ref.read(AppThemeModeProvider.notifier).setMode(v)),
              options: const [
                RA_RadioOption(value: AppThemeModeEnum.Dark, title: 'Dark'),
                RA_RadioOption(value: AppThemeModeEnum.Light, title: 'Light'),
              ],
            ),
          ),
          RA_FormSection(
            label: 'Alarm Layout',
            child: RA_RadioGroup<AlarmSnoozeDismissLayoutEnum>(
              groupValue: layout,
              onChanged: (v) => unawaited(
                ref
                    .read(AlarmSnoozeDismissLayoutProvider.notifier)
                    .setLayout(v),
              ),
              options: const [
                RA_RadioOption(
                  value: AlarmSnoozeDismissLayoutEnum.Sliders,
                  title: 'Sliders',
                ),
                RA_RadioOption(
                  value: AlarmSnoozeDismissLayoutEnum.Buttons,
                  title: 'Buttons',
                ),
              ],
            ),
          ),
          RA_FormSection(
            label: 'Side Buttons',
            child: _SideButtonsTileRow(
              settings: sideButtons,
              onSelect: (button) => unawaited(
                _pickSideButtonAction(context, ref, button, sideButtons),
              ),
            ),
          ),
          RA_FormSection(
            label: 'Swipe Actions',
            child: _SwipeActionsTileRow(
              settings: swipeActions,
              onSelect: (direction) => unawaited(
                _pickSwipeAction(context, ref, direction, swipeActions),
              ),
            ),
          ),
          RA_FormSection(
            label: 'Import/Export',
            child: Column(
              children: [
                _SettingsAction(
                  icon: Icons.file_upload,
                  title: 'Export Routines',
                  subtitle: 'Copy a shareable RA1 string of all routines.',
                  onTap: () => unawaited(_export(context, ref)),
                ),
                const SizedBox(height: RA_ShapeStyles.space8),
                _SettingsAction(
                  icon: Icons.file_download,
                  title: 'Import Routines',
                  subtitle: 'Paste an RA1 string to add routines.',
                  onTap: () => unawaited(_import(context, ref)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickSideButtonAction(
    BuildContext context,
    WidgetRef ref,
    AlarmSideButtonEnum button,
    AlarmSideButtonsSettings settings,
  ) async {
    final selected = await showDialog<AlarmSideButtonActionEnum>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RA_ColourStyles.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: RA_ShapeStyles.largeBorderRadius,
        ),
        title: Text(button.label, style: RA_TextStyles.mediumFont),
        content: RA_RadioGroup<AlarmSideButtonActionEnum>(
          groupValue: settings.actionFor(button),
          onChanged: (v) => Navigator.pop(ctx, v),
          options: const [
            RA_RadioOption(
              value: AlarmSideButtonActionEnum.None,
              title: 'None',
            ),
            RA_RadioOption(
              value: AlarmSideButtonActionEnum.Snooze,
              title: 'Snooze',
            ),
            RA_RadioOption(
              value: AlarmSideButtonActionEnum.Dismiss,
              title: 'Dismiss',
            ),
          ],
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    await ref
        .read(AlarmSideButtonsProvider.notifier)
        .setButtonAction(button: button, action: selected);
  }

  Future<void> _pickSwipeAction(
    BuildContext context,
    WidgetRef ref,
    RoutineSwipeDirectionEnum direction,
    RoutineSwipeActionsSettings settings,
  ) async {
    final selected = await showDialog<RoutineSwipeActionEnum>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RA_ColourStyles.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: RA_ShapeStyles.largeBorderRadius,
        ),
        title: Text(direction.label, style: RA_TextStyles.mediumFont),
        content: RA_RadioGroup<RoutineSwipeActionEnum>(
          groupValue: settings.actionFor(direction),
          onChanged: (v) => Navigator.pop(ctx, v),
          options: const [
            RA_RadioOption(
              value: RoutineSwipeActionEnum.Mute,
              title: 'Mute',
            ),
            RA_RadioOption(
              value: RoutineSwipeActionEnum.Pause,
              title: 'Pause',
            ),
            RA_RadioOption(
              value: RoutineSwipeActionEnum.DismissUpcoming,
              title: 'Dismiss Upcoming',
            ),
            RA_RadioOption(
              value: RoutineSwipeActionEnum.Delete,
              title: 'Delete',
            ),
          ],
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    await ref
        .read(RoutineSwipeActionsProvider.notifier)
        .setDirectionAction(direction: direction, action: selected);
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final db = ref.read(RA_DatabaseProvider);
    final routines = await db.watchAllRoutines().first;
    if (!context.mounted) return;
    if (routines.isEmpty) {
      RA_showNoRoutinesToExportWarning(context);
      return;
    }

    final exportStr = await RA_tryAsync(
      () => RA_ExportService.exportToBase64(db),
    );
    if (exportStr != null && context.mounted) {
      unawaited(RA_showExportDialog(context, exportStr));
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    await RA_showImportDialog(
      context,
      onImport: (text) async {
        final db = ref.read(RA_DatabaseProvider);
        final importedIds = await RA_ExportService.importFromBase64(db, text);
        await _scheduleImported(db, importedIds);
      },
    );
  }

  /// Arms the exact alarm for each freshly imported routine, so an imported
  /// routine rings without needing to be opened and saved again.
  Future<void> _scheduleImported(RA_Database db, List<int> routineIds) async {
    for (final routineId in routineIds) {
      final state = await db.getRoutineState(routineId);
      final next = state?.NextTriggerTime;
      if (next == null) continue;
      final routine = await db.getRoutineById(routineId);
      await RA_AlarmService.scheduleNext(
        routineId: routineId,
        triggerTime: next,
        dbPath: widget.dbPath,
        routineName: routine.Name,
      );
    }
  }
}

/// Equal height tiles for Volume Up / Volume Down side button actions.
class _SideButtonsTileRow extends StatelessWidget {
  final AlarmSideButtonsSettings settings;
  final ValueChanged<AlarmSideButtonEnum> onSelect;

  const _SideButtonsTileRow({required this.settings, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < AlarmSideButtonEnum.values.length; i++) ...[
            if (i > 0) const SizedBox(width: RA_ShapeStyles.space8),
            Expanded(
              child: _SideButtonTile(
                button: AlarmSideButtonEnum.values[i],
                action: settings.actionFor(AlarmSideButtonEnum.values[i]),
                onTap: () => onSelect(AlarmSideButtonEnum.values[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact tappable cell: muted button label over the chosen action.
class _SideButtonTile extends StatelessWidget {
  final AlarmSideButtonEnum button;
  final AlarmSideButtonActionEnum action;
  final VoidCallback onTap;

  const _SideButtonTile({
    required this.button,
    required this.action,
    required this.onTap,
  });

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
          child: DecoratedBox(
            decoration: RA_ShapeStyles.elevatedSurface(),
            child: Padding(
              padding: const EdgeInsets.all(RA_ShapeStyles.space8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RA_FittedText(
                    button.label,
                    alignment: Alignment.center,
                    style: RA_TextStyles.tinyFont.copyWith(
                      color: RA_ColourStyles.mutedPrimary,
                    ),
                  ),
                  const SizedBox(height: RA_ShapeStyles.space8),
                  RA_FittedText(
                    action.label,
                    alignment: Alignment.center,
                    style: RA_TextStyles.smallFont.copyWith(
                      color: RA_ColourStyles.valueText,
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

/// Equal height tiles for Left / Right swipe actions.
class _SwipeActionsTileRow extends StatelessWidget {
  final RoutineSwipeActionsSettings settings;
  final ValueChanged<RoutineSwipeDirectionEnum> onSelect;

  const _SwipeActionsTileRow({
    required this.settings,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < RoutineSwipeDirectionEnum.values.length; i++) ...[
            if (i > 0) const SizedBox(width: RA_ShapeStyles.space8),
            Expanded(
              child: _SwipeActionTile(
                direction: RoutineSwipeDirectionEnum.values[i],
                action: settings.actionFor(
                  RoutineSwipeDirectionEnum.values[i],
                ),
                onTap: () => onSelect(RoutineSwipeDirectionEnum.values[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact tappable cell: muted direction label over the chosen swipe action.
class _SwipeActionTile extends StatelessWidget {
  final RoutineSwipeDirectionEnum direction;
  final RoutineSwipeActionEnum action;
  final VoidCallback onTap;

  const _SwipeActionTile({
    required this.direction,
    required this.action,
    required this.onTap,
  });

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
          child: DecoratedBox(
            decoration: RA_ShapeStyles.elevatedSurface(),
            child: Padding(
              padding: const EdgeInsets.all(RA_ShapeStyles.space8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RA_FittedText(
                    direction.label,
                    alignment: Alignment.center,
                    style: RA_TextStyles.tinyFont.copyWith(
                      color: RA_ColourStyles.mutedPrimary,
                    ),
                  ),
                  const SizedBox(height: RA_ShapeStyles.space8),
                  RA_FittedText(
                    action.label,
                    alignment: Alignment.center,
                    style: RA_TextStyles.smallFont.copyWith(
                      color: action.color,
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

/// Tappable settings row with icon, title, and short supporting text.
class _SettingsAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

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
          child: DecoratedBox(
            decoration: RA_ShapeStyles.elevatedSurface(),
            child: Padding(
              padding: const EdgeInsets.all(RA_ShapeStyles.space16),
              child: Row(
                children: [
                  Icon(icon, color: RA_ColourStyles.secondary),
                  const SizedBox(width: RA_ShapeStyles.space16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: RA_TextStyles.smallFont),
                        const SizedBox(height: RA_ShapeStyles.space8),
                        Text(
                          subtitle,
                          style: RA_TextStyles.tinyFont.copyWith(
                            color: RA_ColourStyles.mutedPrimary,
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
