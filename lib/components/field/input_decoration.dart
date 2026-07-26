import 'package:flutter/material.dart';
import 'package:rolling_alarm/styles.dart';

/// Shared [InputDecoration] chrome for form fields and dense dialog inputs.
InputDecoration RA_InputDecoration({
  String? hintText,
  TextStyle? hintStyle,
  bool dense = false,
  bool hasError = false,
}) {
  final radius = dense
      ? RA_ShapeStyles.tinyBorderRadius
      : RA_ShapeStyles.largeBorderRadius;
  final idleSide = hasError
      ? BorderSide(color: RA_ColourStyles.softCoral, width: 1.5)
      : dense
          ? BorderSide(color: RA_ColourStyles.secondary.withValues(alpha: 0.22))
          : BorderSide(color: RA_ShapeStyles.idleSurfaceBorder);
  final focusedSide = BorderSide(
    color: hasError
        ? RA_ColourStyles.softCoral
        : dense
            ? RA_ColourStyles.secondary.withValues(alpha: 0.75)
            : RA_ColourStyles.secondary.withValues(alpha: 0.4),
    width: 1.5,
  );

  return InputDecoration(
    hintText: hintText,
    hintStyle: hintStyle,
    filled: true,
    fillColor: dense ? RA_ColourStyles.offBlack : RA_ColourStyles.surface,
    contentPadding: const EdgeInsets.all(RA_ShapeStyles.space16),
    border: OutlineInputBorder(
      borderRadius: radius,
      borderSide: hasError ? idleSide : (dense ? idleSide : BorderSide.none),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: idleSide,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: focusedSide,
    ),
  );
}
