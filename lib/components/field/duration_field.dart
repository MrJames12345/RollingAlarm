import 'package:flutter/material.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/press_scale.dart';
import 'package:rolling_alarm/styles.dart';

/// 3 separate inputs (Hours, Minutes, Seconds) with up/down arrows and ability
/// to click into the field to type. Used for routine interval editing.
/// The final result is saved to the single seconds field in db.
class RA_DurationField extends StatelessWidget {
  final String label;
  final Duration value;
  final ValueChanged<Duration> onChanged;
  final Duration max;
  final Duration min;
  final bool hasError;

  const RA_DurationField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.max = const Duration(hours: 23, minutes: 59, seconds: 59),
    this.min = const Duration(seconds: 1),
    this.hasError = false,
  });

  void _updateDuration({int? newHours, int? newMinutes, int? newSeconds}) {
    final int h = newHours ?? value.inHours;
    final int m = newMinutes ?? value.inMinutes.remainder(60);
    final int s = newSeconds ?? value.inSeconds.remainder(60);

    var totalSeconds = h * 3600 + m * 60 + s;
    if (totalSeconds < min.inSeconds) totalSeconds = min.inSeconds;
    if (totalSeconds > max.inSeconds) totalSeconds = max.inSeconds;

    onChanged(Duration(seconds: totalSeconds));
  }

  @override
  Widget build(BuildContext context) {
    final int hours = value.inHours;
    final int minutes = value.inMinutes.remainder(60);
    final int seconds = value.inSeconds.remainder(60);

    final bool canIncrementHours = hours < max.inHours;
    final bool canDecrementHours = hours > 0;

    final bool canIncrementMinutes =
        minutes < 59 &&
        (hours < max.inHours || minutes < max.inMinutes.remainder(60));
    final bool canDecrementMinutes = minutes > 0;

    final bool canIncrementSeconds =
        seconds < 59 && (value.inSeconds + 1 <= max.inSeconds);
    final bool canDecrementSeconds =
        seconds > 0 && (value.inSeconds - 1 >= min.inSeconds);

    return Row(
      children: [
        Expanded(
          child: _DurationUnitField(
            label: 'Hours',
            value: hours,
            onChanged: (h) => _updateDuration(newHours: h),
            minVal: 0,
            maxVal: max.inHours,
            canIncrement: canIncrementHours,
            canDecrement: canDecrementHours,
            hasError: hasError,
          ),
        ),
        const SizedBox(width: RA_ShapeStyles.space8),
        Expanded(
          child: _DurationUnitField(
            label: 'Minutes',
            value: minutes,
            onChanged: (m) => _updateDuration(newMinutes: m),
            minVal: 0,
            maxVal: 59,
            canIncrement: canIncrementMinutes,
            canDecrement: canDecrementMinutes,
            hasError: hasError,
          ),
        ),
        const SizedBox(width: RA_ShapeStyles.space8),
        Expanded(
          child: _DurationUnitField(
            label: 'Seconds',
            value: seconds,
            onChanged: (s) => _updateDuration(newSeconds: s),
            minVal: 0,
            maxVal: 59,
            canIncrement: canIncrementSeconds,
            canDecrement: canDecrementSeconds,
            hasError: hasError,
          ),
        ),
      ],
    );
  }
}

class _DurationUnitField extends StatefulWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int minVal;
  final int maxVal;
  final bool canIncrement;
  final bool canDecrement;
  final bool hasError;
  bool get enabled => true;

  const _DurationUnitField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.minVal,
    required this.maxVal,
    required this.canIncrement,
    required this.canDecrement,
    this.hasError = false,
  });

  @override
  State<_DurationUnitField> createState() => _DurationUnitFieldState();
}

class _DurationUnitFieldState extends State<_DurationUnitField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  String _formatValue(int val) => val.toString().padLeft(2, '0');

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formatValue(widget.value));
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _DurationUnitField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && !_focusNode.hasFocus) {
      _controller.text = _formatValue(widget.value);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    } else {
      final parsed = int.tryParse(_controller.text) ?? widget.value;
      final clamped = parsed.clamp(widget.minVal, widget.maxVal);
      _controller.text = _formatValue(clamped);
      if (clamped != widget.value) {
        widget.onChanged(clamped);
      }
    }
  }

  void _onTextChanged(String text) {
    if (text.isEmpty) {
      if (widget.value != widget.minVal) {
        widget.onChanged(widget.minVal);
      }
      return;
    }
    final parsed = int.tryParse(text);
    if (parsed == null) return;

    if (parsed > widget.maxVal) {
      _controller.text = _formatValue(widget.maxVal);
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      if (widget.value != widget.maxVal) {
        widget.onChanged(widget.maxVal);
      }
    } else {
      final clamped = parsed.clamp(widget.minVal, widget.maxVal);
      if (widget.value != clamped) {
        widget.onChanged(clamped);
      }
    }
  }

  void _increment() {
    RA_Haptics.heavyUnawaited();
    final next = (widget.value + 1).clamp(widget.minVal, widget.maxVal);
    _controller.text = _formatValue(next);
    if (_focusNode.hasFocus) {
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
    widget.onChanged(next);
  }

  void _decrement() {
    RA_Haptics.heavyUnawaited();
    final next = (widget.value - 1).clamp(widget.minVal, widget.maxVal);
    _controller.text = _formatValue(next);
    if (_focusNode.hasFocus) {
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final labelColor =
        widget.enabled
            ? RA_ColourStyles.mutedPrimary
            : RA_ColourStyles.faintPrimary;
    final valueColor =
        widget.enabled
            ? RA_ColourStyles.secondary
            : RA_ColourStyles.mutedPrimary;

    final decoration = widget.hasError
        ? BoxDecoration(
            color: RA_ColourStyles.surface,
            borderRadius: RA_ShapeStyles.largeBorderRadius,
            border: Border.all(color: RA_ColourStyles.softCoral, width: 1.5),
          )
        : RA_ShapeStyles.elevatedSurface();

    return Opacity(
      opacity: widget.enabled ? 1 : 0.55,
      child: DecoratedBox(
        decoration: decoration,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 2, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (widget.enabled) {
                      _focusNode.requestFocus();
                    }
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.label,
                          style: RA_TextStyles.tinyFont.copyWith(
                            color: labelColor,
                          ),
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(height: RA_ShapeStyles.space8),
                      TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        enabled: widget.enabled,
                        keyboardType: TextInputType.number,
                        style: RA_TextStyles.largeFont.copyWith(
                          color: valueColor,
                          fontFeatures: RA_TextStyles.tabularFeatures,
                        ),
                        cursorColor: RA_ColourStyles.secondary,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                        ),
                        onChanged: _onTextChanged,
                        onTapOutside: (_) => _focusNode.unfocus(),
                      ),
                    ],
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _UnitStepperTap(
                    icon: Icons.keyboard_arrow_up,
                    onTap:
                        widget.enabled && widget.canIncrement
                            ? _increment
                            : null,
                  ),
                  _UnitStepperTap(
                    icon: Icons.keyboard_arrow_down,
                    onTap:
                        widget.enabled && widget.canDecrement
                            ? _decrement
                            : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _UnitStepperTap({required IconData icon, required VoidCallback? onTap}) {
  return RA_PressScale(
    enabled: onTap != null,
    pressedScale: 0.9,
    child: IconButton(
      onPressed: onTap,
      icon: Icon(icon),
      color:
          onTap == null
              ? RA_ColourStyles.primary.withValues(alpha: 0.25)
              : RA_ColourStyles.primary,
      splashColor: RA_ColourStyles.secondary.withValues(alpha: 0.2),
      highlightColor: RA_ColourStyles.secondary.withValues(alpha: 0.1),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 38),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    ),
  );
}

