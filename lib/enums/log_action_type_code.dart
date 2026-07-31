import 'package:flutter/material.dart';
import 'package:rolling_alarm/styles.dart';

/// Persisted activity codes for [LogEntries.LogActionTypeCode].
///
/// Indices 0 to 3 must stay aligned with [RA_AlarmActionTypeCodeEnum]
/// (Dismiss, Snooze, Skip, AutoSnooze). Newer lifecycle events append after.
enum LogActionTypeCodeEnum {
  Dismiss,
  Snooze,
  Skip,
  AutoSnooze,
  Create,
  Edit,
  Delete,
  Duplicate,
  Pause,
  Resume,
  Mute,
  Unmute,
  ResetCounter,
  Ring,
}

LogActionTypeCodeEnum? RA_logActionFromCode(int code) =>
    code < LogActionTypeCodeEnum.values.length
        ? LogActionTypeCodeEnum.values[code]
        : null;

extension LogActionTypeCodeDisplay on LogActionTypeCodeEnum {
  /// Label shown on History / Alarm Logs tiles and PDF export.
  String get displayName => switch (this) {
        LogActionTypeCodeEnum.AutoSnooze => 'Auto Snooze',
        LogActionTypeCodeEnum.ResetCounter => 'Reset Counter',
        _ => name,
      };

  Color get color => switch (this) {
        LogActionTypeCodeEnum.Dismiss => RA_ColourStyles.secondary,
        LogActionTypeCodeEnum.Snooze => RA_ColourStyles.sleepIndigo,
        LogActionTypeCodeEnum.Skip => RA_ColourStyles.primary,
        LogActionTypeCodeEnum.AutoSnooze => RA_ColourStyles.softCoral,
        LogActionTypeCodeEnum.Create => RA_ColourStyles.mossGreen,
        LogActionTypeCodeEnum.Edit => RA_ColourStyles.slateBlue,
        LogActionTypeCodeEnum.Delete => RA_ColourStyles.dustyWine,
        LogActionTypeCodeEnum.Duplicate => RA_ColourStyles.softPlum,
        LogActionTypeCodeEnum.Pause => RA_ColourStyles.pauseOchre,
        LogActionTypeCodeEnum.Resume => RA_ColourStyles.oliveMist,
        LogActionTypeCodeEnum.Mute => RA_ColourStyles.mutedViolet,
        LogActionTypeCodeEnum.Unmute => RA_ColourStyles.softSky,
        LogActionTypeCodeEnum.ResetCounter => RA_ColourStyles.warmAmber,
        LogActionTypeCodeEnum.Ring => RA_ColourStyles.ringEmber,
      };

  /// Soft bloom behind log tiles for the most salient action types.
  List<BoxShadow>? get tileGlow => switch (this) {
        LogActionTypeCodeEnum.AutoSnooze => RA_ShapeStyles.softCoralGlow,
        LogActionTypeCodeEnum.Dismiss => RA_ShapeStyles.tealGlow,
        _ => null,
      };
}
