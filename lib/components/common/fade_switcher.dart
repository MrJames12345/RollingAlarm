import 'package:flutter/material.dart';
import 'package:rolling_alarm/styles.dart';

/// Wraps [child] with a [ValueKey] so [AnimatedSwitcher] treats each phase as distinct.
Widget RA_Keyed(String identity, Widget child) =>
    KeyedSubtree(key: ValueKey(identity), child: child);

/// Cross fades between child identities so loading, empty, and data never hard cut.
class RA_FadeSwitcher extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final Curve switchInCurve;
  final Curve switchOutCurve;

  const RA_FadeSwitcher({
    super.key,
    required this.child,
    this.duration = RA_ShapeStyles.pageFadeDuration,
    this.switchInCurve = Curves.easeOut,
    this.switchOutCurve = Curves.easeIn,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: switchInCurve,
      switchOutCurve: switchOutCurve,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: child,
    );
  }
}
