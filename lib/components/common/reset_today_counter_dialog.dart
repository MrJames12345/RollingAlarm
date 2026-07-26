import 'package:flutter/material.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/styles.dart';

/// Asks the user to confirm resetting today's ring counter.
///
/// Returns `true` when Reset is chosen, `false` / `null` when cancelled.
Future<bool?> RA_showResetTodayCounterDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: RA_ColourStyles.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: RA_ShapeStyles.largeBorderRadius,
      ),
      title: Text("Reset today's counter?", style: RA_TextStyles.mediumFont),
      content: Text(
        'This sets today\'s count back to zero.',
        style: RA_TextStyles.smallFont.copyWith(height: 1.35),
      ),
      actions: [
        RA_DialogButton('Cancel', () => Navigator.pop(ctx, false)),
        RA_DialogButton(
          'Reset',
          () => Navigator.pop(ctx, true),
          color: RA_ColourStyles.secondary,
          style: RA_TextStyles.mediumFont,
        ),
      ],
    ),
  );
}
