import 'package:flutter/material.dart';
import 'package:rolling_alarm/styles.dart';

/// Immediate visual tap feedback for primary actions.
class RA_PressScale extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double pressedScale;

  const RA_PressScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressedScale = 0.97,
  });

  @override
  State<RA_PressScale> createState() => _RA_PressScaleState();
}

class _RA_PressScaleState extends State<RA_PressScale> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (!widget.enabled) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: RA_ShapeStyles.pressFeedbackDuration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
