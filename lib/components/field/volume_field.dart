import 'package:flutter/material.dart';
import 'package:rolling_alarm/styles.dart';

/// Volume slider bound to the device hardware alarm stream (0 to 100).
///
/// Moving the slider should call [onChanged], which must forward the value to
/// the native [AudioManager.STREAM_ALARM] MethodChannel wrappers.
Widget RA_VolumeField({
  required int value,
  required ValueChanged<int> onChanged,
}) {
  final clamped = value.clamp(0, 100);

  return DecoratedBox(
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
                  style: RA_TextStyles.tinyFont.copyWith(
                    color: RA_ColourStyles.mutedPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '$clamped%',
                style: RA_TextStyles.smallFont.copyWith(
                  color: RA_ColourStyles.secondary,
                  fontFeatures: RA_TextStyles.tabularFeatures,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: RA_ColourStyles.secondary,
              inactiveTrackColor: RA_ColourStyles.primary.withValues(
                alpha: 0.12,
              ),
              thumbColor: RA_ColourStyles.secondary,
              overlayColor: RA_ColourStyles.secondary.withValues(alpha: 0.16),
              trackHeight: 4,
            ),
            child: Slider(
              value: clamped.toDouble(),
              min: 0,
              max: 100,
              divisions: 20,
              onChanged: (v) => onChanged(v.round().clamp(0, 100)),
            ),
          ),
        ],
      ),
    ),
  );
}
