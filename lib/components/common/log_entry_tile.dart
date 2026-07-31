import 'package:flutter/material.dart';
import 'package:rolling_alarm/components/common/fitted_text.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/press_scale.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/log_action_type_code.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:rolling_alarm/utils.dart';

/// Single alarm lifecycle log row used on the global logs page and
/// routine history tab.
///
/// Pass [routineName] on the global logs page so tiles identify which
/// routine the event belongs to. Omit it on per-routine history.
///
/// When [showRecover] is true (Delete entry for a still soft-deleted
/// routine), a Recover control appears on the right and calls [onRecover].
Widget RA_LogEntryTile({
  required LogEntryModel entry,
  String? routineName,
  bool showRecover = false,
  VoidCallback? onRecover,
}) {
  final action = RA_logActionFromCode(entry.LogActionTypeCode);
  final actionColor = action?.color ?? RA_ColourStyles.primary;
  final resolvedName = routineName?.trim();
  final showRoutineName = resolvedName != null && resolvedName.isNotEmpty;
  final canRecover = showRecover && onRecover != null;

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
                      action?.displayName ?? 'Unknown',
                      style: RA_TextStyles.smallFont.copyWith(
                        color: actionColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (entry.WasMuted) ...[
                      const SizedBox(height: RA_ShapeStyles.space8),
                      Text(
                        'Muted',
                        style: RA_TextStyles.tinyFont.copyWith(
                          color: RA_ColourStyles.sleepIndigo,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (showRoutineName) ...[
                      const SizedBox(height: RA_ShapeStyles.space8),
                      Text(
                        resolvedName,
                        style: RA_TextStyles.tinyFont.copyWith(
                          color: RA_ColourStyles.secondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: RA_ShapeStyles.space8),
                    RA_FittedText(
                      RA_Utils.formatDateTime(entry.Timestamp),
                      style: RA_TextStyles.timestampFont,
                    ),
                  ],
                ),
              ),
              if (canRecover) ...[
                const SizedBox(width: RA_ShapeStyles.space8),
                _RecoverButton(onPressed: onRecover!),
              ] else if (entry.TimeSinceLastDismissalSeconds != null) ...[
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

class _RecoverButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _RecoverButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return RA_PressScale(
      pressedScale: 0.94,
      child: TextButton(
        onPressed: () {
          RA_Haptics.heavyUnawaited();
          onPressed();
        },
        style: TextButton.styleFrom(
          foregroundColor: RA_ColourStyles.recoverSeafoam,
          minimumSize: const Size(
            RA_ShapeStyles.minTouchTarget,
            RA_ShapeStyles.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: RA_ShapeStyles.space8,
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          'Recover',
          style: RA_TextStyles.smallFont.copyWith(
            color: RA_ColourStyles.recoverSeafoam,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
