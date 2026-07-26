import 'package:flutter/material.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/styles.dart';

/// Surface-wrapped switch row for boolean routine settings.
///
/// The whole row is tappable so users are not limited to the switch thumb.
/// Uses a plain [Row] + [Switch] (not [SwitchListTile]) so Material ListTile
/// never injects washed grey tile fills on OLED black.
Widget RA_Toggle({
  required String label,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () {
        RA_Haptics.heavyUnawaited();
        onChanged(!value);
      },
      borderRadius: RA_ShapeStyles.largeBorderRadius,
      splashColor: RA_ColourStyles.secondary.withValues(alpha: 0.16),
      highlightColor: RA_ColourStyles.secondary.withValues(alpha: 0.08),
      child: AnimatedContainer(
        duration: RA_ShapeStyles.stateTransitionDuration,
        curve: Curves.easeOut,
        constraints: const BoxConstraints(
          minHeight: RA_ShapeStyles.minTouchTarget,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: RA_ShapeStyles.space16,
          vertical: RA_ShapeStyles.space8,
        ),
        decoration: RA_ShapeStyles.elevatedSurface(
          borderColor: value
              ? RA_ColourStyles.secondary.withValues(alpha: 0.28)
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: RA_TextStyles.smallFont,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: RA_ShapeStyles.space16),
            SizedBox(
              width: RA_ShapeStyles.minTouchTarget,
              height: RA_ShapeStyles.minTouchTarget,
              child: IgnorePointer(
                child: Switch(
                  value: value,
                  onChanged: (_) {},
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
