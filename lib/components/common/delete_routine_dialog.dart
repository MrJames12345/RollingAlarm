import 'package:flutter/material.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/styles.dart';

/// Asks the user to confirm soft-deleting a routine.
///
/// Returns `true` when Delete is chosen, `false` / `null` when cancelled.
Future<bool?> RA_showDeleteRoutineDialog(
  BuildContext context, {
  required String routineName,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: RA_ColourStyles.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: RA_ShapeStyles.largeBorderRadius,
      ),
      title: Text('Delete routine?', style: RA_TextStyles.mediumFont),
      content: Text(
        'Remove "$routineName" from your list and cancel its alarm? The routine is not permanently erased; you can recover it later from Alarm Logs.',
        style: RA_TextStyles.smallFont.copyWith(height: 1.35),
      ),
      actions: [
        RA_DialogButton('Cancel', () => Navigator.pop(ctx, false)),
        RA_DialogButton(
          'Delete',
          () => Navigator.pop(ctx, true),
          color: RA_ColourStyles.softCoral,
          style: RA_TextStyles.mediumFont,
        ),
      ],
    ),
  );
}
