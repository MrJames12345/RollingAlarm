import 'package:flutter/material.dart';
import 'package:rolling_alarm/components/common/fitted_text.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/log_action_type_code.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:rolling_alarm/utils.dart';

/// Single alarm lifecycle log row used on the global logs page and
/// routine history tab.
Widget RA_LogEntryTile({required LogEntryModel entry}) {
  final action = RA_logActionFromCode(entry.LogActionTypeCode);
  final actionColor = action?.color ?? RA_ColourStyles.primary;

  return Padding(
    padding: const EdgeInsets.only(bottom: RA_ShapeStyles.space8),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: RA_ColourStyles.surface,
        borderRadius: RA_ShapeStyles.largeBorderRadius,
        border: Border.all(
          color: actionColor.withValues(alpha: 0.22),
          width: 1,
        ),
        boxShadow: action?.tileGlow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(RA_ShapeStyles.space16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: RA_ShapeStyles.minTouchTarget + RA_ShapeStyles.space16,
          ),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: actionColor,
                  borderRadius: RA_ShapeStyles.microBorderRadius,
                  boxShadow: [
                    BoxShadow(
                      color: actionColor.withValues(alpha: 0.45),
                      blurRadius: 10,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: const SizedBox(
                  width: RA_ShapeStyles.space8,
                  height: RA_ShapeStyles.minTouchTarget,
                ),
              ),
              const SizedBox(width: RA_ShapeStyles.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action?.name ?? 'Unknown',
                      style: RA_TextStyles.smallFont.copyWith(
                        color: actionColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: RA_ShapeStyles.space8),
                    RA_FittedText(
                      RA_Utils.formatDateTime(entry.Timestamp),
                      style: RA_TextStyles.timestampFont,
                    ),
                  ],
                ),
              ),
              if (entry.TimeSinceLastDismissalSeconds != null) ...[
                const SizedBox(width: RA_ShapeStyles.space8),
                RA_FittedText(
                  RA_Utils.formatSecondsAsDuration(
                    entry.TimeSinceLastDismissalSeconds!,
                  ),
                  style: RA_TextStyles.intervalDigitsFont,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
