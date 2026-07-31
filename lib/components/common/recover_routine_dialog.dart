import 'package:flutter/material.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/styles.dart';

/// Asks the user to confirm recovering a soft-deleted routine.
///
/// Returns `true` when Recover is chosen, `false` / `null` when cancelled.
Future<bool?> RA_showRecoverRoutineDialog(
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
      title: Text('Recover routine?', style: RA_TextStyles.mediumFont),
      content: Text(
        'Recover "$routineName"? It will return to your list and its alarm will be scheduled again.',
        style: RA_TextStyles.smallFont.copyWith(height: 1.35),
      ),
      actions: [
        RA_DialogButton('Cancel', () => Navigator.pop(ctx, false)),
        RA_DialogButton(
          'Recover',
          () => Navigator.pop(ctx, true),
          color: RA_ColourStyles.recoverSeafoam,
          style: RA_TextStyles.mediumFont,
        ),
      ],
    ),
  );
}
