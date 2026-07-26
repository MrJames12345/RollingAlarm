import 'package:flutter/material.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/styles.dart';

/// Asks whether a "Dismiss upcoming" skip should count toward today's total.
///
/// Returns `true` for Yes, `false` for No, and `null` when the dialog is
/// dismissed without a choice (skip is aborted).
Future<bool?> RA_showCountDailySkipDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: RA_ColourStyles.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: RA_ShapeStyles.largeBorderRadius,
      ),
      title: Text(
        'Count this towards your daily counter?',
        style: RA_TextStyles.mediumFont,
      ),
      actions: [
        RA_DialogButton('No', () => Navigator.pop(ctx, false)),
        RA_DialogButton(
          'Yes',
          () => Navigator.pop(ctx, true),
          color: RA_ColourStyles.secondary,
          style: RA_TextStyles.mediumFont,
        ),
      ],
    ),
  );
}
