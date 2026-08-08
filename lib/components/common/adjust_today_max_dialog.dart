import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/styles.dart';

/// Asks the user to enter a new max limit for today.
///
/// Returns the new max number when submitted, `null` when cancelled.
Future<int?> RA_showAdjustTodayMaxDialog(
  BuildContext context, {
  required int currentMax,
}) {
  final controller = TextEditingController(text: currentMax.toString());

  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: RA_ColourStyles.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: RA_ShapeStyles.largeBorderRadius,
      ),
      contentPadding: const EdgeInsets.fromLTRB(
        RA_ShapeStyles.space24,
        RA_ShapeStyles.space16,
        RA_ShapeStyles.space24,
        RA_ShapeStyles.space8,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        RA_ShapeStyles.space8,
        0,
        RA_ShapeStyles.space8,
        RA_ShapeStyles.space8,
      ),
      content: StatefulBuilder(
        builder: (context, setState) {
          void updateCount(int delta) {
            final val = int.tryParse(controller.text) ?? currentMax;
            final newVal = val + delta;
            if (newVal >= 0) {
              controller.text = newVal.toString();
              controller.selection = TextSelection.fromPosition(
                TextPosition(offset: controller.text.length),
              );
            }
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter the new max limit for today.',
                style: RA_TextStyles.smallFont.copyWith(height: 1.35),
              ),
              const SizedBox(height: RA_ShapeStyles.space16),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () => updateCount(-1),
                    color: RA_ColourStyles.primary,
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: RA_TextStyles.mediumFont,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: 'e.g. 1',
                        hintStyle: RA_TextStyles.mediumFont.copyWith(
                          color: RA_ColourStyles.mutedPrimary,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: RA_ColourStyles.faintPrimary,
                          ),
                          borderRadius: RA_ShapeStyles.tinyBorderRadius,
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(
                            color: RA_ColourStyles.secondary,
                          ),
                          borderRadius: RA_ShapeStyles.tinyBorderRadius,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: RA_ShapeStyles.space16,
                          vertical: 12,
                        ),
                      ),
                      autofocus: true,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => updateCount(1),
                    color: RA_ColourStyles.primary,
                  ),
                ],
              ),
            ],
          );
        },
      ),
      actions: [
        RA_DialogButton('Cancel', () => Navigator.pop(ctx, null)),
        RA_DialogButton('Set', () {
          final val = int.tryParse(controller.text);
          if (val != null && val >= 0) {
            Navigator.pop(ctx, val);
          }
        }, color: RA_ColourStyles.secondary),
      ],
    ),
  );
}
