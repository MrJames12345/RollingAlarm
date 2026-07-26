import 'package:flutter/material.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/press_scale.dart';
import 'package:rolling_alarm/styles.dart';

/// Side-by-side [RA_NumberField] pair used on snooze forms.
Widget RA_NumberFieldRow({required Widget left, required Widget right}) {
  return Row(
    children: [
      Expanded(child: left),
      const SizedBox(width: RA_ShapeStyles.space16),
      Expanded(child: right),
    ],
  );
}

/// Integer stepper field for minute values.
Widget RA_NumberField({
  required String label,
  required int value,
  required ValueChanged<int> onChanged,
  required int min,
  required int max,
  bool enabled = true,
}) {
  final labelColor = enabled
      ? RA_ColourStyles.mutedPrimary
      : RA_ColourStyles.faintPrimary;
  final valueColor = enabled
      ? RA_ColourStyles.secondary
      : RA_ColourStyles.mutedPrimary;

  return Opacity(
    opacity: enabled ? 1 : 0.55,
    child: DecoratedBox(
      decoration: RA_ShapeStyles.elevatedSurface(),
      child: Padding(
        padding: const EdgeInsets.all(RA_ShapeStyles.space16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: RA_TextStyles.tinyFont.copyWith(color: labelColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: RA_ShapeStyles.space8),
                  AnimatedSwitcher(
                    duration: RA_ShapeStyles.pressFeedbackDuration * 2,
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.2),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Text(
                      '$value',
                      key: ValueKey(value),
                      style: RA_TextStyles.largeFont.copyWith(
                        color: valueColor,
                        fontFeatures: RA_TextStyles.tabularFeatures,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                _StepperTap(
                  icon: Icons.keyboard_arrow_up,
                  onTap: enabled && value < max
                      ? () {
                          RA_Haptics.heavyUnawaited();
                          onChanged(value + 1);
                        }
                      : null,
                ),
                _StepperTap(
                  icon: Icons.keyboard_arrow_down,
                  onTap: enabled && value > min
                      ? () {
                          RA_Haptics.heavyUnawaited();
                          onChanged(value - 1);
                        }
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _StepperTap({required IconData icon, required VoidCallback? onTap}) {
  return RA_PressScale(
    enabled: onTap != null,
    pressedScale: 0.9,
    child: IconButton(
      onPressed: onTap,
      icon: Icon(icon),
      color: onTap == null
          ? RA_ColourStyles.primary.withValues(alpha: 0.25)
          : RA_ColourStyles.primary,
      splashColor: RA_ColourStyles.secondary.withValues(alpha: 0.2),
      highlightColor: RA_ColourStyles.secondary.withValues(alpha: 0.1),
      constraints: const BoxConstraints(
        minWidth: RA_ShapeStyles.minTouchTarget,
        minHeight: RA_ShapeStyles.minTouchTarget,
      ),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    ),
  );
}
