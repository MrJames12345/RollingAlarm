import 'package:flutter/material.dart';
import 'package:rolling_alarm/components/common/section_label.dart';
import 'package:rolling_alarm/components/field/input_decoration.dart';
import 'package:rolling_alarm/styles.dart';

/// Labeled single-line text field used on routine edit forms.
Widget RA_TextField({
  required TextEditingController controller,
  String? label,
  String? placeholder,
  String? errorText,
  ValueChanged<String>? onChanged,
  FocusNode? focusNode,
  bool autofocus = false,
}) {
  final hasError = errorText != null && errorText.isNotEmpty;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (label != null && label.isNotEmpty) ...[
        RA_SectionLabel(label, errorText: errorText),
        const SizedBox(height: RA_ShapeStyles.space8),
      ],
      ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: RA_ShapeStyles.minTouchTarget,
        ),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          style: RA_TextStyles.mediumFont,
          cursorColor: RA_ColourStyles.secondary,
          textCapitalization: TextCapitalization.words,
          onChanged: onChanged,
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          decoration: RA_InputDecoration(
            hintText: placeholder,
            hintStyle: RA_TextStyles.mediumFont.copyWith(
              color: RA_ColourStyles.faintPrimary,
            ),
            hasError: hasError,
          ),
        ),
      ),
    ],
  );
}
