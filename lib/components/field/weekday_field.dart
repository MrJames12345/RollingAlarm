import 'package:flutter/material.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/services/weekday_schedule.dart';
import 'package:rolling_alarm/styles.dart';

/// Seven tappable day buttons (MTWTFSS). At least one day must stay enabled.
Widget RA_WeekdayField({
  required int value,
  required ValueChanged<int> onChanged,
}) {
  return Row(
    children: [
      for (var i = 0; i < 7; i++) ...[
        if (i > 0) const SizedBox(width: RA_ShapeStyles.space8),
        Expanded(
          child: _WeekdayButton(
            label: RA_WeekdaySchedule.dayLabels[i],
            enabled: RA_WeekdaySchedule.isEnabled(value, i + 1),
            onTap: () {
              RA_Haptics.heavyUnawaited();
              onChanged(RA_WeekdaySchedule.toggleWeekday(value, i + 1));
            },
          ),
        ),
      ],
    ],
  );
}

class _WeekdayButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _WeekdayButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: RA_ShapeStyles.largeBorderRadius,
        splashColor: RA_ColourStyles.secondary.withValues(alpha: 0.16),
        highlightColor: RA_ColourStyles.secondary.withValues(alpha: 0.08),
        child: AnimatedContainer(
          duration: RA_ShapeStyles.stateTransitionDuration,
          curve: Curves.easeOut,
          alignment: Alignment.center,
          constraints: const BoxConstraints(
            minHeight: RA_ShapeStyles.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(vertical: RA_ShapeStyles.space8),
          decoration: RA_ShapeStyles.elevatedSurface(
            borderColor: enabled
                ? RA_ColourStyles.secondary.withValues(alpha: 0.28)
                : null,
            fill: enabled
                ? RA_ColourStyles.secondary.withValues(alpha: 0.12)
                : null,
          ),
          child: Text(
            label,
            style: RA_TextStyles.smallFont.copyWith(
              color: enabled
                  ? RA_ColourStyles.primary
                  : RA_ColourStyles.faintPrimary,
              fontWeight: enabled ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
