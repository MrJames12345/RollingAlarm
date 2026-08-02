import 'package:rolling_alarm/enums/alarm_side_button_action.dart';
import 'package:rolling_alarm/enums/alarm_snooze_dismiss_layout.dart';
import 'package:rolling_alarm/enums/app_theme_mode.dart';
import 'package:rolling_alarm/enums/routine_swipe_action.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide user preferences backed by SharedPreferences.
class RA_SettingsService {
  static const String alarmSnoozeDismissLayoutKey =
      'ra_alarm_snooze_dismiss_layout';
  static const String themeModeKey = 'ra_theme_mode';
  static const String sideButtonVolumeUpKey = 'ra_side_button_volume_up';
  static const String sideButtonVolumeDownKey = 'ra_side_button_volume_down';
  static const String swipeActionLeftKey = 'ra_swipe_action_left';
  static const String swipeActionRightKey = 'ra_swipe_action_right';
  static const String cardButtonLeftKey = 'ra_card_button_left';
  static const String cardButtonRightKey = 'ra_card_button_right';

  static Future<AlarmSnoozeDismissLayoutEnum>
  getAlarmSnoozeDismissLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(alarmSnoozeDismissLayoutKey);
    if (index == null ||
        index < 0 ||
        index >= AlarmSnoozeDismissLayoutEnum.values.length) {
      return AlarmSnoozeDismissLayoutEnum.Sliders;
    }
    return AlarmSnoozeDismissLayoutEnum.values[index];
  }

  static Future<void> setAlarmSnoozeDismissLayout(
    AlarmSnoozeDismissLayoutEnum layout,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(alarmSnoozeDismissLayoutKey, layout.index);
  }

  static Future<AppThemeModeEnum> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(themeModeKey);
    if (index == null || index < 0 || index >= AppThemeModeEnum.values.length) {
      return AppThemeModeEnum.Dark;
    }
    return AppThemeModeEnum.values[index];
  }

  static Future<void> setThemeMode(AppThemeModeEnum mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(themeModeKey, mode.index);
  }

  static Future<AlarmSideButtonsSettings> getSideButtons() async {
    final prefs = await SharedPreferences.getInstance();
    return AlarmSideButtonsSettings(
      volumeUp: _readSideButtonAction(prefs, sideButtonVolumeUpKey),
      volumeDown: _readSideButtonAction(prefs, sideButtonVolumeDownKey),
    );
  }

  static Future<void> setSideButtons(AlarmSideButtonsSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(sideButtonVolumeUpKey, settings.volumeUp.index);
    await prefs.setInt(sideButtonVolumeDownKey, settings.volumeDown.index);
  }

  static Future<void> setSideButtonAction({
    required AlarmSideButtonEnum button,
    required AlarmSideButtonActionEnum action,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = switch (button) {
      AlarmSideButtonEnum.VolumeUp => sideButtonVolumeUpKey,
      AlarmSideButtonEnum.VolumeDown => sideButtonVolumeDownKey,
    };
    await prefs.setInt(key, action.index);
  }

  static AlarmSideButtonActionEnum _readSideButtonAction(
    SharedPreferences prefs,
    String key,
  ) {
    final index = prefs.getInt(key);
    if (index == null ||
        index < 0 ||
        index >= AlarmSideButtonActionEnum.values.length) {
      return AlarmSideButtonActionEnum.None;
    }
    return AlarmSideButtonActionEnum.values[index];
  }

  static Future<RoutineSwipeActionsSettings> getSwipeActions() async {
    final prefs = await SharedPreferences.getInstance();
    return RoutineSwipeActionsSettings(
      left: _readSwipeAction(
        prefs,
        swipeActionLeftKey,
        RoutineSwipeActionEnum.Delete,
      ),
      right: _readSwipeAction(
        prefs,
        swipeActionRightKey,
        RoutineSwipeActionEnum.Pause,
      ),
    );
  }

  static Future<void> setSwipeAction({
    required RoutineSwipeDirectionEnum direction,
    required RoutineSwipeActionEnum action,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = switch (direction) {
      RoutineSwipeDirectionEnum.Left => swipeActionLeftKey,
      RoutineSwipeDirectionEnum.Right => swipeActionRightKey,
    };
    await prefs.setInt(key, action.index);
  }

  static RoutineSwipeActionEnum _readSwipeAction(
    SharedPreferences prefs,
    String key,
    RoutineSwipeActionEnum fallback,
  ) {
    final index = prefs.getInt(key);
    if (index == null ||
        index < 0 ||
        index >= RoutineSwipeActionEnum.values.length) {
      return fallback;
    }
    return RoutineSwipeActionEnum.values[index];
  }

  static Future<RoutineCardButtonsSettings> getCardButtons() async {
    final prefs = await SharedPreferences.getInstance();
    return RoutineCardButtonsSettings(
      left: _readSwipeAction(
        prefs,
        cardButtonLeftKey,
        RoutineSwipeActionEnum.AddForToday,
      ),
      right: _readSwipeAction(
        prefs,
        cardButtonRightKey,
        RoutineSwipeActionEnum.ResetInterval,
      ),
    );
  }

  static Future<void> setCardButtonAction({
    required RoutineCardButtonPositionEnum position,
    required RoutineSwipeActionEnum action,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = switch (position) {
      RoutineCardButtonPositionEnum.Left => cardButtonLeftKey,
      RoutineCardButtonPositionEnum.Right => cardButtonRightKey,
    };
    await prefs.setInt(key, action.index);
  }
}
