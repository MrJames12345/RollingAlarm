import 'package:flutter/material.dart';
import 'package:rolling_alarm/styles.dart';

/// Subtle Pro pill badge used on gated controls when the user is on Free tier.
class RA_ProBadge extends StatelessWidget {
  final String label;
  final Color? color;

  const RA_ProBadge({
    super.key,
    this.label = 'PRO',
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final accent = color ?? RA_ColourStyles.secondary;
    final textColor = RA_ColourStyles.readableAccent(accent);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: RA_ShapeStyles.tinyBorderRadius,
        border: Border.all(
          color: accent.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RA_ShapeStyles.space8,
          vertical: 2,
        ),
        child: Text(
          label,
          style: RA_TextStyles.tinyFont.copyWith(
            color: textColor,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}
