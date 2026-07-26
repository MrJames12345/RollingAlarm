import 'package:flutter/material.dart';
import 'package:rolling_alarm/styles.dart';

/// Root navigator used to present [AlarmRingPage] above any other route.
final GlobalKey<NavigatorState> RA_navigatorKey = GlobalKey<NavigatorState>();

/// Shared page transitions for fluid navigation between app screens.
class RA_Routes {
  RA_Routes._();

  static const String alarmRingName = 'ra_alarm_ring';

  static CurvedAnimation _curve(Animation<double> animation) => CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// Soft fade used for secondary screens (logs, settings, edit).
  static Route<T> fade<T extends Object?>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: RA_ShapeStyles.pageFadeDuration,
      reverseTransitionDuration: const Duration(milliseconds: 220),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: _curve(animation), child: child),
    );
  }

  /// Urgent enter animation for the full screen alarm ring page.
  static Route<T> alarmRing<T extends Object?>(Widget page) {
    return PageRouteBuilder<T>(
      opaque: true,
      settings: const RouteSettings(name: alarmRingName),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: RA_ShapeStyles.stateTransitionDuration,
      reverseTransitionDuration: const Duration(milliseconds: 240),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = _curve(animation);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}
