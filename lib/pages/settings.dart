import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/components/common/form_section.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/import_export_dialogs.dart';
import 'package:rolling_alarm/components/common/page_scaffold.dart';
import 'package:rolling_alarm/components/common/press_scale.dart';
import 'package:rolling_alarm/database/database.dart';
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
    return RA_PageScaffold(
      title: 'Settings',
      body: ListView(
        padding: RA_ShapeStyles.bodyPadding,
        children: [
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

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final exportStr = await RA_tryAsync(
      () => RA_ExportService.exportToBase64(ref.read(RA_DatabaseProvider)),
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
