import 'package:flutter/material.dart';
import 'package:rolling_alarm/styles.dart';

/// Section header label used on edit and settings surfaces.
Widget RA_SectionLabel(String text, {String? errorText}) {
  final hasError = errorText != null && errorText.isNotEmpty;
  return Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text(
        text,
        style: RA_TextStyles.smallFont.copyWith(
          color: hasError
              ? RA_ColourStyles.softCoral
              : RA_ColourStyles.secondary,
        ),
      ),
      if (hasError) ...[
        const SizedBox(width: RA_ShapeStyles.space8),
        Text(
          '— $errorText',
          style: RA_TextStyles.tinyFont.copyWith(
            color: RA_ColourStyles.softCoral,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ],
  );
}
