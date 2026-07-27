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
enum AlarmSideButtonEnum { VolumeUp, VolumeDown, Power }

extension AlarmSideButtonEnumX on AlarmSideButtonEnum {
  String get label => switch (this) {
    AlarmSideButtonEnum.VolumeUp => 'Volume Up',
    AlarmSideButtonEnum.VolumeDown => 'Volume Down',
    AlarmSideButtonEnum.Power => 'Power',
  };
}

/// Persisted mapping of each side button to an alarm action.
class AlarmSideButtonsSettings {
  final AlarmSideButtonActionEnum volumeUp;
  final AlarmSideButtonActionEnum volumeDown;
  final AlarmSideButtonActionEnum power;

  const AlarmSideButtonsSettings({
    this.volumeUp = AlarmSideButtonActionEnum.None,
    this.volumeDown = AlarmSideButtonActionEnum.None,
    this.power = AlarmSideButtonActionEnum.None,
  });

  AlarmSideButtonActionEnum actionFor(AlarmSideButtonEnum button) {
    return switch (button) {
      AlarmSideButtonEnum.VolumeUp => volumeUp,
      AlarmSideButtonEnum.VolumeDown => volumeDown,
      AlarmSideButtonEnum.Power => power,
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
        power: power,
      ),
      AlarmSideButtonEnum.VolumeDown => AlarmSideButtonsSettings(
        volumeUp: volumeUp,
        volumeDown: action,
        power: power,
      ),
      AlarmSideButtonEnum.Power => AlarmSideButtonsSettings(
        volumeUp: volumeUp,
        volumeDown: volumeDown,
        power: action,
      ),
    };
  }
}
