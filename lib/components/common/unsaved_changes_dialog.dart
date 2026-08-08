import 'package:flutter/material.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/styles.dart';

/// User choice from [RA_showUnsavedChangesDialog].
///
/// `null` means Cancel or dismiss without continuing.
enum RA_UnsavedChangesChoice {
  discardAndContinue,
  saveAndContinue,
}

/// Asks how to handle leaving (or continuing) with unsaved routine edits.
Future<RA_UnsavedChangesChoice?> RA_showUnsavedChangesDialog(
  BuildContext context, {
  required String routineName,
}) {
  return showDialog<RA_UnsavedChangesChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: RA_ColourStyles.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: RA_ShapeStyles.largeBorderRadius,
      ),
      content: Text(
        'You have unsaved changes to "$routineName".',
        style: RA_TextStyles.smallFont.copyWith(height: 1.35),
      ),
      actions: [
        RA_DialogButton(
          'Cancel',
          () => Navigator.pop(ctx),
        ),
        RA_DialogButton(
          'Discard & Continue',
          () => Navigator.pop(ctx, RA_UnsavedChangesChoice.discardAndContinue),
        ),
        RA_DialogButton(
          'Save & Continue',
          () => Navigator.pop(ctx, RA_UnsavedChangesChoice.saveAndContinue),
          color: RA_ColourStyles.secondary,
        ),
      ],
    ),
  );
}
