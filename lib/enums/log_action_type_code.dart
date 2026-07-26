import 'package:flutter/material.dart';
import 'package:rolling_alarm/styles.dart';

enum LogActionTypeCodeEnum {
  Dismiss,
  Snooze,
  Skip,
  AutoSnooze,
}

LogActionTypeCodeEnum? RA_logActionFromCode(int code) =>
    code < LogActionTypeCodeEnum.values.length
        ? LogActionTypeCodeEnum.values[code]
        : null;

extension LogActionTypeCodeDisplay on LogActionTypeCodeEnum {
  Color get color => switch (this) {
        LogActionTypeCodeEnum.Dismiss => RA_ColourStyles.secondary,
        LogActionTypeCodeEnum.Snooze => RA_ColourStyles.sleepIndigo,
        LogActionTypeCodeEnum.Skip => RA_ColourStyles.primary,
        LogActionTypeCodeEnum.AutoSnooze => RA_ColourStyles.softCoral,
      };

  /// Soft bloom behind log tiles for the most salient action types.
  List<BoxShadow>? get tileGlow => switch (this) {
        LogActionTypeCodeEnum.AutoSnooze => RA_ShapeStyles.softCoralGlow,
        LogActionTypeCodeEnum.Dismiss => RA_ShapeStyles.tealGlow,
        LogActionTypeCodeEnum.Snooze || LogActionTypeCodeEnum.Skip => null,
      };
}
