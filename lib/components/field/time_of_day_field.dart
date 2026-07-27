import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/press_scale.dart';
import 'package:rolling_alarm/styles.dart';

/// Tappable clock-time field (hours and minutes) for day-boundary settings.
///
/// When [label] is null or empty, the tappable surface shows only the formatted
/// time on the left and a clock icon on the right. Use [pickerTitle] for the
/// sheet header when the in-field label is omitted.
class RA_TimeOfDayField extends StatelessWidget {
  final String? label;
  final String? pickerTitle;
  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onChanged;
  final bool enabled;

  const RA_TimeOfDayField({
    super.key,
    this.label,
    this.pickerTitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  String get _sheetTitle {
    final fromPicker = pickerTitle?.trim();
    if (fromPicker != null && fromPicker.isNotEmpty) return fromPicker;
    final fromLabel = label?.trim();
    if (fromLabel != null && fromLabel.isNotEmpty) return fromLabel;
    return 'Time';
  }

  bool get _showInFieldLabel {
    final text = label?.trim();
    return text != null && text.isNotEmpty;
  }

  DateTime _asDateTime(TimeOfDay tod) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
  }

  Future<void> _openPicker(BuildContext context) async {
    if (!enabled) return;
    RA_Haptics.heavyUnawaited();
    var draft = value;

    final confirmed = await showModalBottomSheet<TimeOfDay>(
      context: context,
      backgroundColor: RA_ColourStyles.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          maintainBottomViewPadding: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              RA_ShapeStyles.space16,
              RA_ShapeStyles.space16,
              RA_ShapeStyles.space16,
              RA_ShapeStyles.space8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(_sheetTitle, style: RA_TextStyles.mediumFont),
                    ),
                    RA_DialogButton(
                      'Cancel',
                      () => Navigator.pop(sheetContext),
                    ),
                    RA_DialogButton(
                      'Done',
                      () => Navigator.pop(sheetContext, draft),
                      color: RA_ColourStyles.secondary,
                    ),
                  ],
                ),
                const SizedBox(height: RA_ShapeStyles.space8),
                SizedBox(
                  height: 196,
                  child: CupertinoTheme(
                    data: CupertinoThemeData(
                      brightness: RA_ColourStyles.brightness,
                      primaryColor: RA_ColourStyles.secondary,
                      textTheme: CupertinoTextThemeData(
                        dateTimePickerTextStyle: RA_TextStyles.largeFont
                            .copyWith(color: RA_ColourStyles.primary),
                      ),
                    ),
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.time,
                      initialDateTime: _asDateTime(draft),
                      use24hFormat: MediaQuery.alwaysUse24HourFormatOf(context),
                      onDateTimeChanged: (next) {
                        draft = TimeOfDay(hour: next.hour, minute: next.minute);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != null) {
      onChanged(confirmed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final labelText = DateFormat.jm().format(_asDateTime(value));
    final labelColor = enabled
        ? RA_ColourStyles.mutedPrimary
        : RA_ColourStyles.faintPrimary;
    final valueColor = enabled
        ? RA_ColourStyles.valueText
        : RA_ColourStyles.mutedPrimary;

    final timeText = AnimatedSwitcher(
      duration: RA_ShapeStyles.pressFeedbackDuration * 2,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.2),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: Text(
        labelText,
        key: ValueKey(labelText),
        style: RA_TextStyles.largeFont.copyWith(
          color: valueColor,
          fontFeatures: RA_TextStyles.tabularFeatures,
        ),
      ),
    );

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: RA_PressScale(
        enabled: enabled,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? () => _openPicker(context) : null,
            borderRadius: RA_ShapeStyles.largeBorderRadius,
            splashColor: RA_ColourStyles.secondary.withValues(alpha: 0.16),
            highlightColor: RA_ColourStyles.secondary.withValues(alpha: 0.08),
            child: Ink(
              decoration: RA_ShapeStyles.elevatedSurface(),
              child: Padding(
                padding: const EdgeInsets.all(RA_ShapeStyles.space16),
                child: Row(
                  children: [
                    Expanded(
                      child: _showInFieldLabel
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label!.trim(),
                                  style: RA_TextStyles.tinyFont.copyWith(
                                    color: labelColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: RA_ShapeStyles.space8),
                                timeText,
                              ],
                            )
                          : timeText,
                    ),
                    Icon(Icons.access_time, color: labelColor),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
