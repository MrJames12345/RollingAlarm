import 'package:flutter/material.dart';
import 'package:rolling_alarm/components/common/section_label.dart';
import 'package:rolling_alarm/styles.dart';

/// Labeled form block with consistent vertical rhythm.
Widget RA_FormSection({
  required String label,
  required Widget child,
  String? errorText,
  double bottomSpacing = RA_ShapeStyles.space24,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      RA_SectionLabel(label, errorText: errorText),
      const SizedBox(height: RA_ShapeStyles.space8),
      child,
      SizedBox(height: bottomSpacing),
    ],
  );
}
