import 'package:flutter/material.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/press_scale.dart';
import 'package:rolling_alarm/enums/app_theme_mode.dart';
import 'package:rolling_alarm/styles.dart';

/// Primary action button matching Rolling Alarm chrome.
///
/// Uses immediate scale press feedback plus heavy haptic on tap.
Widget RA_Button({
  required String text,
  required VoidCallback? onClick,
  bool isPrimary = true,
  Color? backgroundColor,
  Color? foregroundColor,
  Color? sideColor,
  Color? shadowColor,
}) {
  final bg =
      backgroundColor ??
      (isPrimary ? RA_ColourStyles.secondary : RA_ColourStyles.surface);
  final fg =
      foregroundColor ??
      (isPrimary ? RA_ColourStyles.onAccent : RA_ColourStyles.primary);
  final side =
      sideColor ??
      (isPrimary
          ? null
          : RA_ColourStyles.secondary.withValues(
              alpha: RA_ColourStyles.mode == AppThemeModeEnum.Light ? 0.4 : 0.3,
            ));

  return RA_PressScale(
    enabled: onClick != null,
    child: ElevatedButton(
      onPressed: onClick == null
          ? null
          : () {
              RA_Haptics.heavyUnawaited();
              onClick();
            },
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        minimumSize: const Size(double.infinity, 56),
        side: side == null ? null : BorderSide(color: side, width: 1.5),
        elevation: isPrimary ? 2 : 0,
        shadowColor: shadowColor ??
            RA_ColourStyles.secondary.withValues(alpha: 0.35),
        // M3 surface tint would wash teal/coral fills toward grey on OLED.
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: RA_ShapeStyles.largeBorderRadius,
        ),
        splashFactory: InkSparkle.splashFactory,
      ),
      child: Text(
        text,
        style: RA_TextStyles.mediumFont.copyWith(color: fg),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}

/// Compact text action used in dialogs, app bars, and status retry rows.
Widget RA_DialogButton(
  String text,
  VoidCallback onTap, {
  Color? color,
  TextStyle? style,
}) {
  final base = style ?? RA_TextStyles.smallFont;
  return ConstrainedBox(
    constraints: const BoxConstraints(
      minWidth: RA_ShapeStyles.minTouchTarget,
      minHeight: RA_ShapeStyles.minTouchTarget,
    ),
    child: TextButton(
      onPressed: () {
        RA_Haptics.heavyUnawaited();
        onTap();
      },
      child: Text(
        text,
        style: base.copyWith(color: color ?? RA_ColourStyles.primary),
      ),
    ),
  );
}

/// AppBar icon action with the Material minimum touch target and press scale.
Widget RA_AppBarIconButton({
  required IconData icon,
  required VoidCallback onPressed,
  String? tooltip,
}) {
  return RA_PressScale(
    pressedScale: 0.9,
    child: IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      constraints: const BoxConstraints(
        minWidth: RA_ShapeStyles.minTouchTarget,
        minHeight: RA_ShapeStyles.minTouchTarget,
      ),
      onPressed: () {
        RA_Haptics.heavyUnawaited();
        onPressed();
      },
    ),
  );
}

/// Compact icon + label tap target used on routine cards and dense toolbars.
Widget RA_IconTextButton({
  required IconData icon,
  required String label,
  required VoidCallback onTap,
  Color? color,
}) {
  final c = color ?? RA_ColourStyles.primary.withValues(alpha: 0.7);
  return RA_PressScale(
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          RA_Haptics.heavyUnawaited();
          onTap();
        },
        borderRadius: RA_ShapeStyles.tinyBorderRadius,
        splashColor: c.withValues(alpha: 0.2),
        highlightColor: c.withValues(alpha: 0.1),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: RA_ShapeStyles.minTouchTarget,
            minHeight: RA_ShapeStyles.minTouchTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RA_ShapeStyles.space16,
              vertical: RA_ShapeStyles.space8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: c),
                const SizedBox(width: RA_ShapeStyles.space8),
                Text(label, style: RA_TextStyles.tinyFont.copyWith(color: c)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
