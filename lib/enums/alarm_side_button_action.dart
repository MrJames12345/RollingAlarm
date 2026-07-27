/// What a hardware side button does while an alarm is ringing.
enum AlarmSideButtonActionEnum { None, Snooze, Dismiss }

extension AlarmSideButtonActionEnumX on AlarmSideButtonActionEnum {
  String get label => switch (this) {
    AlarmSideButtonActionEnum.None => 'None',
    AlarmSideButtonActionEnum.Snooze => 'Snooze',
    AlarmSideButtonActionEnum.Dismiss => 'Dismiss',
  };
}

/// Which physical side button the setting applies to.
enum AlarmSideButtonEnum { VolumeUp, VolumeDown }

extension AlarmSideButtonEnumX on AlarmSideButtonEnum {
  String get label => switch (this) {
    AlarmSideButtonEnum.VolumeUp => 'Volume Up',
    AlarmSideButtonEnum.VolumeDown => 'Volume Down',
  };
}

/// Persisted mapping of each side button to an alarm action.
class AlarmSideButtonsSettings {
  final AlarmSideButtonActionEnum volumeUp;
  final AlarmSideButtonActionEnum volumeDown;

  const AlarmSideButtonsSettings({
    this.volumeUp = AlarmSideButtonActionEnum.None,
    this.volumeDown = AlarmSideButtonActionEnum.None,
  });

  AlarmSideButtonActionEnum actionFor(AlarmSideButtonEnum button) {
    return switch (button) {
      AlarmSideButtonEnum.VolumeUp => volumeUp,
      AlarmSideButtonEnum.VolumeDown => volumeDown,
    };
  }

  AlarmSideButtonsSettings copyWithButton({
    required AlarmSideButtonEnum button,
    required AlarmSideButtonActionEnum action,
  }) {
    return switch (button) {
      AlarmSideButtonEnum.VolumeUp => AlarmSideButtonsSettings(
        volumeUp: action,
        volumeDown: volumeDown,
      ),
      AlarmSideButtonEnum.VolumeDown => AlarmSideButtonsSettings(
        volumeUp: volumeUp,
        volumeDown: action,
      ),
    };
  }
}
