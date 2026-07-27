import 'package:flutter/material.dart';
import 'package:rolling_alarm/styles.dart';

/// Action performed when swiping a home routine card left or right.
enum RoutineSwipeActionEnum { Mute, Pause, DismissUpcoming, Delete }

extension RoutineSwipeActionEnumX on RoutineSwipeActionEnum {
  String get label => switch (this) {
    RoutineSwipeActionEnum.Mute => 'Mute',
    RoutineSwipeActionEnum.Pause => 'Pause',
    RoutineSwipeActionEnum.DismissUpcoming => 'Dismiss Upcoming',
    RoutineSwipeActionEnum.Delete => 'Delete',
  };

  /// Swipe reveal background colour for this action.
  Color get color => switch (this) {
    RoutineSwipeActionEnum.Mute => RA_ColourStyles.sleepIndigo,
    RoutineSwipeActionEnum.Pause => RA_ColourStyles.pauseOchre,
    RoutineSwipeActionEnum.DismissUpcoming => RA_ColourStyles.secondary,
    RoutineSwipeActionEnum.Delete => RA_ColourStyles.softCoral,
  };

  IconData get icon => switch (this) {
    RoutineSwipeActionEnum.Mute => Icons.notifications_off_outlined,
    RoutineSwipeActionEnum.Pause => Icons.pause_rounded,
    RoutineSwipeActionEnum.DismissUpcoming => Icons.skip_next,
    RoutineSwipeActionEnum.Delete => Icons.delete_outline,
  };
}

/// Which horizontal swipe direction the setting applies to.
enum RoutineSwipeDirectionEnum { Left, Right }

extension RoutineSwipeDirectionEnumX on RoutineSwipeDirectionEnum {
  String get label => switch (this) {
    RoutineSwipeDirectionEnum.Left => 'Left',
    RoutineSwipeDirectionEnum.Right => 'Right',
  };
}

/// Persisted left/right swipe actions for home routine cards.
class RoutineSwipeActionsSettings {
  final RoutineSwipeActionEnum left;
  final RoutineSwipeActionEnum right;

  const RoutineSwipeActionsSettings({
    this.left = RoutineSwipeActionEnum.Delete,
    this.right = RoutineSwipeActionEnum.Pause,
  });

  RoutineSwipeActionEnum actionFor(RoutineSwipeDirectionEnum direction) {
    return switch (direction) {
      RoutineSwipeDirectionEnum.Left => left,
      RoutineSwipeDirectionEnum.Right => right,
    };
  }

  RoutineSwipeActionsSettings copyWithDirection({
    required RoutineSwipeDirectionEnum direction,
    required RoutineSwipeActionEnum action,
  }) {
    return switch (direction) {
      RoutineSwipeDirectionEnum.Left => RoutineSwipeActionsSettings(
        left: action,
        right: right,
      ),
      RoutineSwipeDirectionEnum.Right => RoutineSwipeActionsSettings(
        left: left,
        right: action,
      ),
    };
  }
}
