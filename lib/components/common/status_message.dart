import 'package:flutter/material.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/enums/app_theme_mode.dart';
import 'package:rolling_alarm/styles.dart';

/// Centered empty or error message used by list pages so the UI never
/// falls through to a blank scaffold or a raw exception string.
class RA_StatusMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color? accentColor;
  final String? actionLabel;
  final VoidCallback? onAction;

  const RA_StatusMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.accentColor,
    this.actionLabel,
    this.onAction,
  });

  /// Friendly error surface without stack traces or exception toString().
  factory RA_StatusMessage.error({
    Key? key,
    required String title,
    String message =
        'Something went wrong while loading this screen. Please try again.',
    VoidCallback? onRetry,
  }) {
    return RA_StatusMessage(
      key: key,
      icon: Icons.error_outline,
      title: title,
      message: message,
      accentColor: RA_ColourStyles.softCoral,
      actionLabel: onRetry != null ? 'Try Again' : null,
      onAction: onRetry,
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? RA_ColourStyles.secondary;
    final isAlert = accent == RA_ColourStyles.softCoral;
    final isLight = RA_ColourStyles.mode == AppThemeModeEnum.Light;

    // Light: soft accent wash so the disc reads on warm paper; dark: charcoal.
    final circleFill = isLight
        ? accent.withValues(alpha: 0.14)
        : RA_ColourStyles.surface;
    final circleBorder = accent.withValues(alpha: isLight ? 0.4 : 0.28);
    final iconColor = accent.withValues(alpha: isLight ? 1 : 0.85);
    // Light empty/error copy stays near-black for contrast on paper.
    final titleColor = isLight
        ? RA_ColourStyles.onAccent
        : RA_ColourStyles.primary.withValues(alpha: 0.9);
    final messageColor = isLight
        ? RA_ColourStyles.onAccent.withValues(alpha: 0.72)
        : RA_ColourStyles.mutedPrimary;

    return Semantics(
      header: true,
      label: '$title. $message',
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(RA_ShapeStyles.space32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.92, end: 1),
                  duration: RA_ShapeStyles.stateTransitionDuration,
                  curve: Curves.easeOut,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: circleFill,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: circleBorder,
                        width: 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(RA_ShapeStyles.space24),
                      child: Icon(
                        icon,
                        size: RA_ShapeStyles.space48,
                        color: iconColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: RA_ShapeStyles.space24),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: RA_TextStyles.mediumFont.copyWith(
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: RA_ShapeStyles.space8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: RA_TextStyles.smallFont.copyWith(
                    color: messageColor,
                    height: 1.4,
                  ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: RA_ShapeStyles.space24),
                  RA_DialogButton(
                    actionLabel!,
                    onAction!,
                    color: isAlert
                        ? RA_ColourStyles.softCoral
                        : RA_ColourStyles.secondary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
