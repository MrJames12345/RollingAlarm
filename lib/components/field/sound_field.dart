import 'package:flutter/material.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/press_scale.dart';
import 'package:rolling_alarm/enums/alarm_sound_source.dart';
import 'package:rolling_alarm/models/alarm_sound.dart';
import 'package:rolling_alarm/styles.dart';

/// Tappable sound summary used on the routine editor.
Widget RA_SoundField({
  required RA_AlarmSound value,
  required VoidCallback onTap,
}) {
  return RA_PressScale(
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          RA_Haptics.heavyUnawaited();
          onTap();
        },
        borderRadius: RA_ShapeStyles.largeBorderRadius,
        splashColor: RA_ColourStyles.secondary.withValues(alpha: 0.16),
        highlightColor: RA_ColourStyles.secondary.withValues(alpha: 0.08),
        child: Ink(
          decoration: RA_ShapeStyles.elevatedSurface(),
          child: Padding(
            padding: const EdgeInsets.all(RA_ShapeStyles.space16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sound',
                        style: RA_TextStyles.tinyFont.copyWith(
                          color: RA_ColourStyles.mutedPrimary,
                        ),
                      ),
                      const SizedBox(height: RA_ShapeStyles.space8),
                      Text(
                        value.displayLabel,
                        style: RA_TextStyles.largeFont.copyWith(
                          color: RA_ColourStyles.secondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: RA_ShapeStyles.space8),
                      Text(
                        value.source.label,
                        style: RA_TextStyles.tinyFont.copyWith(
                          color: RA_ColourStyles.mutedPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.music_note,
                  color: RA_ColourStyles.mutedPrimary,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
