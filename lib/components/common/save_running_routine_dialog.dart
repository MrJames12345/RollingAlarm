import 'package:flutter/material.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/press_scale.dart';
import 'package:rolling_alarm/styles.dart';

/// Choice when saving an edit while a routine timer is already running.
enum RA_RunningRoutineSaveChoice {
  continueCurrent,
  skipCurrent,
}

/// Confirms how to apply edits when the routine still has an active timer.
Future<RA_RunningRoutineSaveChoice?> RA_showRunningRoutineSaveDialog(
  BuildContext context,
) {
  return showDialog<RA_RunningRoutineSaveChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: RA_ColourStyles.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: RA_ShapeStyles.largeBorderRadius,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'This routine is currently running. Your new config will apply on the next timer.',
            style: RA_TextStyles.smallFont.copyWith(height: 1.35),
          ),
          const SizedBox(height: RA_ShapeStyles.space24),
          _ChoiceButton(
            label: 'Continue with current timer',
            isPrimary: true,
            onTap: () => Navigator.pop(
              ctx,
              RA_RunningRoutineSaveChoice.continueCurrent,
            ),
          ),
          const SizedBox(height: RA_ShapeStyles.space8),
          _ChoiceButton(
            label: 'Skip current timer',
            isPrimary: false,
            onTap: () => Navigator.pop(
              ctx,
              RA_RunningRoutineSaveChoice.skipCurrent,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _ChoiceButton({
  required String label,
  required bool isPrimary,
  required VoidCallback onTap,
}) {
  final bg = isPrimary ? RA_ColourStyles.secondary : RA_ColourStyles.offBlack;
  final fg = isPrimary ? RA_ColourStyles.offBlack : RA_ColourStyles.primary;
  final side = isPrimary
      ? null
      : BorderSide(color: RA_ColourStyles.secondary.withValues(alpha: 0.3));

  return RA_PressScale(
    child: ElevatedButton(
      onPressed: () {
        RA_Haptics.heavyUnawaited();
        onTap();
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        minimumSize: const Size(double.infinity, 56),
        padding: const EdgeInsets.symmetric(
          horizontal: RA_ShapeStyles.space16,
          vertical: RA_ShapeStyles.space8,
        ),
        side: side,
        elevation: isPrimary ? 2 : 0,
        shadowColor: RA_ColourStyles.secondary.withValues(alpha: 0.35),
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: RA_ShapeStyles.largeBorderRadius,
        ),
        splashFactory: InkSparkle.splashFactory,
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: RA_TextStyles.smallFont.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
