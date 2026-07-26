import 'package:flutter/material.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/styles.dart';

/// Option model for [RA_RadioGroup].
class RA_RadioOption<T> {
  final T value;
  final String title;
  final String? subtitle;

  const RA_RadioOption({
    required this.value,
    required this.title,
    this.subtitle,
  });
}

/// Surface-wrapped radio list for enum-like choices.
Widget RA_RadioGroup<T>({
  required T groupValue,
  required List<RA_RadioOption<T>> options,
  required ValueChanged<T> onChanged,
}) {
  return ClipRRect(
    borderRadius: RA_ShapeStyles.largeBorderRadius,
    child: DecoratedBox(
      decoration: RA_ShapeStyles.elevatedSurface(),
      child: Column(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: RA_ColourStyles.offBlack.withValues(alpha: 0.55),
              ),
            _RadioTile<T>(
              option: options[i],
              groupValue: groupValue,
              onChanged: onChanged,
            ),
          ],
        ],
      ),
    ),
  );
}

class _RadioTile<T> extends StatelessWidget {
  final RA_RadioOption<T> option;
  final T groupValue;
  final ValueChanged<T> onChanged;

  const _RadioTile({
    required this.option,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = option.value == groupValue;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          RA_Haptics.heavyUnawaited();
          onChanged(option.value);
        },
        splashColor: RA_ColourStyles.secondary.withValues(alpha: 0.18),
        highlightColor: RA_ColourStyles.secondary.withValues(alpha: 0.08),
        child: AnimatedContainer(
          duration: RA_ShapeStyles.stateTransitionDuration,
          curve: Curves.easeOut,
          color: selected
              ? RA_ColourStyles.secondary.withValues(alpha: 0.08)
              : Colors.transparent,
          constraints: const BoxConstraints(
            minHeight: RA_ShapeStyles.minTouchTarget,
          ),
          padding: const EdgeInsets.all(RA_ShapeStyles.space16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  key: ValueKey(selected),
                  size: 22,
                  color: selected
                      ? RA_ColourStyles.secondary
                      : RA_ColourStyles.mutedPrimary,
                ),
              ),
              const SizedBox(width: RA_ShapeStyles.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.title,
                      style: RA_TextStyles.smallFont.copyWith(
                        color: selected
                            ? RA_ColourStyles.secondary
                            : RA_ColourStyles.primary,
                      ),
                    ),
                    if (option.subtitle != null) ...[
                      const SizedBox(height: RA_ShapeStyles.space8),
                      Text(
                        option.subtitle!,
                        style: RA_TextStyles.tinyFont.copyWith(
                          color: RA_ColourStyles.mutedPrimary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
