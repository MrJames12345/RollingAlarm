import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/components/field/input_decoration.dart';
import 'package:rolling_alarm/services/export.dart';
import 'package:rolling_alarm/styles.dart';

Future<void> RA_showExportDialog(BuildContext context, String exportStr) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Export Routines', style: RA_TextStyles.mediumFont),
      content: SingleChildScrollView(
        child: SelectableText(
          exportStr,
          style: RA_TextStyles.tinyFont.copyWith(
            fontFeatures: RA_TextStyles.tabularFeatures,
            height: 1.4,
          ),
        ),
      ),
      actions: [
        RA_DialogButton('Copy', () {
          unawaited(Clipboard.setData(ClipboardData(text: exportStr)));
          Navigator.pop(ctx);
        }, color: RA_ColourStyles.secondary),
        RA_DialogButton('Close', () => Navigator.pop(ctx)),
      ],
    ),
  );
}

/// Warns that export has nothing to share when the routine list is empty.
void RA_showNoRoutinesToExportWarning(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: RA_ColourStyles.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: RA_ShapeStyles.largeBorderRadius,
      ),
      content: Text(
        'No routines to export. Create a routine first.',
        style: RA_TextStyles.smallFont.copyWith(
          color: RA_ColourStyles.softCoral,
        ),
      ),
    ),
  );
}

Future<void> RA_showImportDialog(
  BuildContext context, {
  required Future<bool> Function(String text) onImport,
}) {
  return showDialog(
    context: context,
    builder: (ctx) => _ImportRoutinesDialog(
      hostContext: context,
      onImport: onImport,
    ),
  );
}

class _ImportRoutinesDialog extends StatefulWidget {
  final BuildContext hostContext;
  final Future<bool> Function(String text) onImport;

  const _ImportRoutinesDialog({
    required this.hostContext,
    required this.onImport,
  });

  @override
  State<_ImportRoutinesDialog> createState() => _ImportRoutinesDialogState();
}

class _ImportRoutinesDialogState extends State<_ImportRoutinesDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _importing = false;
  bool _autoDetectedFromClipboard = false;

  @override
  void initState() {
    super.initState();
    unawaited(_detectClipboardPreset());
  }

  Future<void> _detectClipboardPreset() async {
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted || _controller.text.trim().isNotEmpty) return;
      final token = RA_ExportService.tryExtractValidPreset(clip?.text);
      if (token == null) return;
      setState(() {
        _controller.text = token;
        _autoDetectedFromClipboard = true;
      });
    } catch (_) {
      // Clipboard unavailable in headless / restricted environments.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_importing) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _importing = true;
    try {
      final shouldClose = await widget.onImport(text);
      if (shouldClose && mounted) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (!widget.hostContext.mounted) return;
      ScaffoldMessenger.of(widget.hostContext).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: RA_ColourStyles.surface,
          shape: RoundedRectangleBorder(
            borderRadius: RA_ShapeStyles.largeBorderRadius,
            side: BorderSide(color: RA_ShapeStyles.idleSurfaceBorder),
          ),
          content: Text(
            'Import failed. Check the RA1 code or preset link and try again.',
            style: RA_TextStyles.smallFont.copyWith(
              color: RA_ColourStyles.softCoral,
            ),
          ),
        ),
      );
    } finally {
      _importing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Import Routines', style: RA_TextStyles.mediumFont),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_autoDetectedFromClipboard) ...[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: RA_ColourStyles.secondary.withValues(alpha: 0.14),
                  borderRadius: RA_ShapeStyles.tinyBorderRadius,
                  border: Border.all(
                    color: RA_ColourStyles.secondary.withValues(alpha: 0.45),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RA_ShapeStyles.space8,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.content_paste_go_rounded,
                        size: 16,
                        color: RA_ColourStyles.readableAccent(
                          RA_ColourStyles.secondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Preset detected from clipboard — tap Import to add.',
                          style: RA_TextStyles.tinyFont.copyWith(
                            fontSize: 12,
                            color: RA_ColourStyles.readableAccent(
                              RA_ColourStyles.secondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: RA_ShapeStyles.space8),
            ],
            TextField(
              controller: _controller,
              autofocus: true,
              style: RA_TextStyles.tinyFont.copyWith(height: 1.35),
              maxLines: 3,
              decoration: RA_InputDecoration(
                dense: true,
                hintText: 'Paste an RA1:... code or preset link',
                hintStyle: RA_TextStyles.tinyFont.copyWith(
                  color: RA_ColourStyles.mutedPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        RA_DialogButton(
          'Import',
          () => unawaited(_submit()),
          color: RA_ColourStyles.secondary,
        ),
        RA_DialogButton('Cancel', () => Navigator.pop(context)),
      ],
    );
  }
}
