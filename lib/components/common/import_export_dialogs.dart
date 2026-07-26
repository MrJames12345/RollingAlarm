import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/components/field/input_decoration.dart';
import 'package:rolling_alarm/styles.dart';

Future<void> RA_showExportDialog(BuildContext context, String exportStr) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Export Routines', style: RA_TextStyles.mediumFont),
      content: SelectableText(
        exportStr,
        style: RA_TextStyles.tinyFont.copyWith(
          fontFeatures: RA_TextStyles.tabularFeatures,
          height: 1.4,
        ),
      ),
      actions: [
        RA_DialogButton(
          'Copy',
          () {
            unawaited(Clipboard.setData(ClipboardData(text: exportStr)));
            Navigator.pop(ctx);
          },
          color: RA_ColourStyles.secondary,
        ),
        RA_DialogButton('Close', () => Navigator.pop(ctx)),
      ],
    ),
  );
}

Future<void> RA_showImportDialog(
  BuildContext context, {
  required Future<void> Function(String text) onImport,
}) {
  final controller = TextEditingController();
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Import Routines', style: RA_TextStyles.mediumFont),
      content: TextField(
        controller: controller,
        style: RA_TextStyles.tinyFont.copyWith(height: 1.35),
        maxLines: 3,
        decoration: RA_InputDecoration(
          dense: true,
          hintText: 'Paste RA1:... string here',
          hintStyle: RA_TextStyles.tinyFont.copyWith(
            color: RA_ColourStyles.mutedPrimary,
          ),
        ),
      ),
      actions: [
        RA_DialogButton(
          'Import',
          () async {
            final text = controller.text.trim();
            if (text.isEmpty) return;
            try {
              await onImport(text);
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (_) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: RA_ColourStyles.surface,
                  shape: const RoundedRectangleBorder(
                    borderRadius: RA_ShapeStyles.largeBorderRadius,
                  ),
                  content: Text(
                    'Import failed. Check the RA1 string and try again.',
                    style: RA_TextStyles.smallFont.copyWith(
                      color: RA_ColourStyles.softCoral,
                    ),
                  ),
                ),
              );
            }
          },
          color: RA_ColourStyles.secondary,
        ),
        RA_DialogButton('Cancel', () => Navigator.pop(ctx)),
      ],
    ),
  ).whenComplete(controller.dispose);
}
