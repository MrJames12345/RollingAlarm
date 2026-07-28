import 'package:flutter/material.dart';
import 'package:rolling_alarm/enums/app_theme_mode.dart';
import 'package:rolling_alarm/styles.dart';

/// Volume slider bound to the device hardware alarm stream (5 to 100).
///
/// Moving the slider should call [onChanged], which must forward the value to
/// the native [AudioManager.STREAM_ALARM] MethodChannel wrappers.
/// When [enabled] is false (e.g. Silent sound), the slider is non-interactive.
Widget RA_VolumeField({
  required int value,
  required ValueChanged<int> onChanged,
  bool enabled = true,
}) {
  final clamped = value.clamp(5, 100);
  final labelColor = enabled
      ? RA_ColourStyles.mutedPrimary
      : RA_ColourStyles.mutedPrimary.withValues(alpha: 0.45);
  final valueColor = enabled
      ? RA_ColourStyles.valueText
      : RA_ColourStyles.mutedPrimary.withValues(alpha: 0.55);
  final activeTrack = enabled
      ? RA_ColourStyles.secondary
      : RA_ColourStyles.mutedPrimary.withValues(alpha: 0.35);
  final inactiveTrack = RA_ColourStyles.primary.withValues(
    alpha: enabled
        ? (RA_ColourStyles.mode == AppThemeModeEnum.Light ? 0.18 : 0.12)
        : (RA_ColourStyles.mode == AppThemeModeEnum.Light ? 0.1 : 0.06),
  );
  final thumb = enabled
      ? RA_ColourStyles.secondary
      : RA_ColourStyles.mutedPrimary.withValues(alpha: 0.45);

  return Opacity(
    opacity: enabled ? 1 : 0.72,
    child: DecoratedBox(
      decoration: RA_ShapeStyles.elevatedSurface(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RA_ShapeStyles.space16,
          RA_ShapeStyles.space16,
          RA_ShapeStyles.space16,
          RA_ShapeStyles.space8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Volume',
                    style: RA_TextStyles.tinyFont.copyWith(color: labelColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$clamped%',
                  style: RA_TextStyles.smallFont.copyWith(
                    color: valueColor,
                    fontFeatures: RA_TextStyles.tabularFeatures,
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: activeTrack,
                inactiveTrackColor: inactiveTrack,
                thumbColor: thumb,
                disabledActiveTrackColor: activeTrack,
                disabledInactiveTrackColor: inactiveTrack,
                disabledThumbColor: thumb,
                overlayColor: RA_ColourStyles.secondary.withValues(alpha: 0.16),
                trackHeight: 4,
              ),
              child: Slider(
                value: clamped.toDouble(),
                min: 5,
                max: 100,
                divisions: 19,
                onChanged: enabled
                    ? (v) => onChanged(v.round().clamp(5, 100))
                    : null,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
