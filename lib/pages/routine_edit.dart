import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/components/common/form_section.dart';
import 'package:rolling_alarm/components/common/page_scaffold.dart';
import 'package:rolling_alarm/components/common/section_label.dart';
import 'package:rolling_alarm/components/field/duration_field.dart';
import 'package:rolling_alarm/components/field/number_field.dart';
import 'package:rolling_alarm/components/field/radio_group.dart';
import 'package:rolling_alarm/components/field/sound_field.dart';
import 'package:rolling_alarm/components/field/text_field.dart';
import 'package:rolling_alarm/components/field/time_of_day_field.dart';
import 'package:rolling_alarm/components/field/toggle.dart';
import 'package:rolling_alarm/components/field/volume_field.dart';
import 'package:rolling_alarm/components/field/weekday_field.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';
import 'package:rolling_alarm/enums/routine_edit_field.dart';
import 'package:rolling_alarm/models/alarm_sound.dart';
import 'package:rolling_alarm/navigation/routes.dart';
import 'package:rolling_alarm/pages/alarm_ring.dart';
import 'package:rolling_alarm/pages/alarm_sound_picker.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/daily_ring_limit.dart';
import 'package:rolling_alarm/services/weekday_schedule.dart';
import 'package:rolling_alarm/services/widget.dart';
import 'package:rolling_alarm/styles.dart';

class RoutineEditPage extends ConsumerStatefulWidget {
  final String dbPath;
  final RoutineModel? existingRoutine;

  /// When set, scrolls to this field after open and briefly highlights it.
  final RoutineEditFieldEnum? scrollToField;

  const RoutineEditPage({
    super.key,
    required this.dbPath,
    this.existingRoutine,
    this.scrollToField,
  });

  @override
  ConsumerState<RoutineEditPage> createState() => _RoutineEditPageState();
}

class _RoutineEditPageState extends ConsumerState<RoutineEditPage> {
  late TextEditingController _nameController;
  final FocusNode _nameFocusNode = FocusNode();
  Duration _interval = const Duration(hours: 2, minutes: 30);
  Duration _snoozeDuration = const Duration(minutes: 5);
  bool _maxTimesPerDayEnabled = false;
  int _maxTimesPerDay = 1;
  TimeOfDay _dayStart = const TimeOfDay(hour: 0, minute: 0);
  int _enabledWeekdays = RA_WeekdaySchedule.allDaysMask;
  DriftCompensationTypeCodeEnum _compensation =
      DriftCompensationTypeCodeEnum.ActualDismissal;
  RA_AlarmSound _sound = RA_AlarmSound.deviceDefault;
  bool _vibrate = true;
  int _volume = 50;
  bool _fadeIn = false;
  bool _showValidationErrors = false;

  final GlobalKey _nameFieldKey = GlobalKey();
  final GlobalKey _soundFieldKey = GlobalKey();
  final GlobalKey _volumeFieldKey = GlobalKey();
  final GlobalKey _fadeInFieldKey = GlobalKey();
  final GlobalKey _vibrateFieldKey = GlobalKey();
  final GlobalKey _intervalFieldKey = GlobalKey();
  final GlobalKey _snoozeFieldKey = GlobalKey();
  final GlobalKey _maxTimesPerDayFieldKey = GlobalKey();
  final GlobalKey _maxTimesLimitFieldKey = GlobalKey();
  final GlobalKey _dayStartFieldKey = GlobalKey();
  final GlobalKey _driftCompensationFieldKey = GlobalKey();
  final GlobalKey _daysFieldKey = GlobalKey();

  RoutineEditFieldEnum? _highlightedField;

  bool get _isEditing => widget.existingRoutine != null;

  String? get _nameError =>
      _showValidationErrors && _nameController.text.trim().isEmpty
      ? 'Needs value'
      : null;

  String? get _intervalError =>
      _showValidationErrors && _interval.inSeconds < 1 ? 'Needs value' : null;

  String? get _snoozeError =>
      _showValidationErrors && _snoozeDuration.inSeconds < 1
      ? 'Needs value'
      : null;

  /// First invalid required field key, in form order.
  GlobalKey? get _firstInvalidFieldKey {
    if (_nameError != null) return _nameFieldKey;
    if (_intervalError != null) return _intervalFieldKey;
    if (_snoozeError != null) return _snoozeFieldKey;
    return null;
  }

  GlobalKey _keyFor(RoutineEditFieldEnum field) => switch (field) {
    RoutineEditFieldEnum.sound => _soundFieldKey,
    RoutineEditFieldEnum.volume => _volumeFieldKey,
    RoutineEditFieldEnum.fadeIn => _fadeInFieldKey,
    RoutineEditFieldEnum.vibrate => _vibrateFieldKey,
    RoutineEditFieldEnum.interval => _intervalFieldKey,
    RoutineEditFieldEnum.snooze => _snoozeFieldKey,
    RoutineEditFieldEnum.maxTimesPerDay => _maxTimesPerDayFieldKey,
    RoutineEditFieldEnum.maxTimesLimit => _maxTimesLimitFieldKey,
    RoutineEditFieldEnum.dayStart => _dayStartFieldKey,
    RoutineEditFieldEnum.driftCompensation => _driftCompensationFieldKey,
    RoutineEditFieldEnum.days => _daysFieldKey,
  };

  /// Keeps edit state on [allDaysMask], never raw `0`, so Day Start enablement
  /// does not flicker between 0 and 127 when meaning "every day."
  int _normalizeEnabledWeekdays(int mask) =>
      RA_WeekdaySchedule.effectiveMask(mask);

  bool get _hasDisabledWeekday =>
      !RA_WeekdaySchedule.isEveryDay(_enabledWeekdays);

  bool get _dayStartEnabled =>
      _maxTimesPerDayEnabled || _hasDisabledWeekday;

  @override
  void initState() {
    super.initState();
    final r = widget.existingRoutine;
    _nameController = TextEditingController(text: r?.Name ?? '');
    if (r != null) {
      _interval = Duration(seconds: r.IntervalSeconds);
      _snoozeDuration = Duration(seconds: r.SnoozeSeconds);
      _maxTimesPerDayEnabled = r.MaxTimesPerDayEnabled;
      _maxTimesPerDay = r.MaxTimesPerDay < 1 ? 1 : r.MaxTimesPerDay;
      final dayStart = RA_DailyRingLimit.normalizeDayStartSeconds(
        r.DayStartSeconds,
      );
      _dayStart = TimeOfDay(
        hour: dayStart ~/ 3600,
        minute: (dayStart % 3600) ~/ 60,
      );
      _enabledWeekdays = _normalizeEnabledWeekdays(r.EnabledWeekdays);
      _compensation =
          DriftCompensationTypeCodeEnum.values[r.DriftCompensationTypeCode];
      _sound = RA_AlarmSound.decode(r.AudioUri);
      _vibrate = r.Vibrate;
      _volume = r.Volume.clamp(5, 100);
      _fadeIn = r.FadeIn;
    } else {
      unawaited(RA_AlarmService.setSystemAlarmVolume(0.5));
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusNameField());
    }

    final scrollTo = widget.scrollToField;
    if (scrollTo != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_scrollToAndHighlight(scrollTo));
      });
    }
  }

  /// Focuses Name on New Routine so typing can start immediately.
  void _focusNameField() {
    if (!mounted) return;
    _nameFocusNode.requestFocus();
  }

  void _onVolumeChanged(int value) {
    final clamped = value.clamp(5, 100);
    setState(() => _volume = clamped);
    unawaited(RA_AlarmService.setSystemAlarmVolume(clamped / 100.0));
  }

  @override
  void dispose() {
    _nameFocusNode.dispose();
    _nameController.dispose();
    super.dispose();
  }

  RoutinesCompanion _companion({int? id}) {
    final encoded = _sound.encode();
    return RoutinesCompanion(
      Id: id == null ? const Value.absent() : Value(id),
      Name: Value(_nameController.text.trim()),
      IntervalSeconds: Value(_interval.inSeconds),
      SnoozeSeconds: Value(_snoozeDuration.inSeconds),
      MaxTimesPerDayEnabled: Value(_maxTimesPerDayEnabled),
      MaxTimesPerDay: Value(_maxTimesPerDay),
      DayStartSeconds: Value(
        RA_DailyRingLimit.normalizeDayStartSeconds(
          _dayStart.hour * 3600 + _dayStart.minute * 60,
        ),
      ),
      EnabledWeekdays: Value(_enabledWeekdays),
      DriftCompensationTypeCode: Value(_compensation.index),
      ShowPreview: const Value(true),
      Vibrate: Value(_vibrate),
      Volume: Value(_volume.clamp(5, 100)),
      FadeIn: Value(_fadeIn),
      AudioUri: Value(encoded.isEmpty ? null : encoded),
    );
  }

  Future<void> _pickSound() async {
    final picked = await Navigator.of(context).push<RA_AlarmSound>(
      RA_Routes.fade(AlarmSoundPickerPage(initial: _sound)),
    );
    if (picked != null && mounted) {
      setState(() => _sound = picked);
    }
  }

  /// Opens the real alarm UI with current form values; snooze/dismiss only pop.
  Future<void> _previewAlarm() async {
    final name = _nameController.text.trim();
    final encoded = _sound.encode();
    await Navigator.of(context).push<void>(
      RA_Routes.alarmRing(
        AlarmRingPage(
          routineId: 0,
          routineName: name.isEmpty ? 'Alarm' : name,
          audioUri: encoded.isEmpty ? null : encoded,
          vibrate: _vibrate,
          volume: _volume,
          fadeIn: _sound.isSilent ? false : _fadeIn,
          isPreview: true,
        ),
      ),
    );
  }

  Future<void> _scrollToField(GlobalKey key) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final fieldContext = key.currentContext;
    if (fieldContext == null || !fieldContext.mounted) return;
    await Scrollable.ensureVisible(
      fieldContext,
      duration: RA_ShapeStyles.stateTransitionDuration,
      curve: Curves.easeOut,
      alignment: 0.1,
    );
  }

  /// Scrolls to [field] after the page fade, then briefly highlights it.
  Future<void> _scrollToAndHighlight(RoutineEditFieldEnum field) async {
    await Future<void>.delayed(RA_ShapeStyles.pageFadeDuration);
    if (!mounted) return;
    await _scrollToField(_keyFor(field));
    if (!mounted) return;
    setState(() => _highlightedField = field);
    // Hold briefly so the target is obvious, then ease the wash out.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() => _highlightedField = null);
  }

  Future<void> _save() async {
    setState(() => _showValidationErrors = true);
    final invalidKey = _firstInvalidFieldKey;
    if (invalidKey != null) {
      unawaited(_scrollToField(invalidKey));
      return;
    }

    try {
      final db = ref.read(RA_DatabaseProvider);
      final name = _nameController.text.trim();

      if (_isEditing) {
        final existing = widget.existingRoutine!;
        final id = existing.Id;
        final state = await db.getRoutineState(id);
        final oldDayStart = RA_DailyRingLimit.normalizeDayStartSeconds(
          existing.DayStartSeconds,
        );
        final newDayStart = RA_DailyRingLimit.normalizeDayStartSeconds(
          _dayStart.hour * 3600 + _dayStart.minute * 60,
        );
        final previousNext = state?.NextTriggerTime;

        await db.updateRoutine(_companion(id: id));

        // Keep the active timer as-is so interval / other edits apply next
        // cycle. Retarget when day-start changes while waiting on that
        // boundary, or when the daily cap crosses today's count.
        final next = RA_DailyRingLimit.retargetNextAfterEdit(
          previousNext: previousNext,
          oldDayStartSeconds: oldDayStart,
          newDayStartSeconds: newDayStart,
          oldMaxTimesPerDayEnabled: existing.MaxTimesPerDayEnabled,
          newMaxTimesPerDayEnabled: _maxTimesPerDayEnabled,
          oldMaxTimesPerDay: existing.MaxTimesPerDay,
          newMaxTimesPerDay: _maxTimesPerDay,
          timesRingToday: state?.TimesRingToday ?? 0,
          timesRingDay: state?.TimesRingDay,
          now: DateTime.now(),
          intervalSeconds: _interval.inSeconds,
          enabledWeekdays: _enabledWeekdays,
        );
        if (next != null) {
          if (previousNext == null ||
              next.millisecondsSinceEpoch !=
                  previousNext.millisecondsSinceEpoch) {
            await db.updateRoutineState(
              id,
              RoutineStatesCompanion(NextTriggerTime: Value(next)),
            );
          }
          await RA_AlarmService.scheduleNext(
            routineId: id,
            triggerTime: next,
            dbPath: widget.dbPath,
            routineName: name,
            refreshWidget: false,
          );
        }
        await RA_WidgetService.updateWidgetState(db: db);
      } else {
        final dayStartSeconds = RA_DailyRingLimit.normalizeDayStartSeconds(
          _dayStart.hour * 3600 + _dayStart.minute * 60,
        );
        final nextTrigger = RA_DailyRingLimit.initialTriggerTime(
          now: DateTime.now(),
          interval: _interval,
          maxTimesPerDayEnabled: _maxTimesPerDayEnabled,
          dayStartSeconds: dayStartSeconds,
          enabledWeekdays: _enabledWeekdays,
        );
        final routineId = await db.insertRoutineWithInitialState(
          routine: _companion(),
          nextTriggerTime: nextTrigger,
        );
        await RA_AlarmService.scheduleNext(
          routineId: routineId,
          triggerTime: nextTrigger,
          dbPath: widget.dbPath,
          routineName: name,
          refreshWidget: false,
        );
        await RA_WidgetService.updateWidgetState(db: db);
      }

      if (mounted) Navigator.pop(context);
    } catch (_) {
      // Persist / schedule failures still leave the editor.
      if (mounted) Navigator.pop(context);
    }
  }

  Widget _highlightTarget({
    required RoutineEditFieldEnum field,
    required GlobalKey key,
    required Widget child,
  }) {
    return KeyedSubtree(
      key: key,
      child: _FieldFocusHighlight(
        active: _highlightedField == field,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RA_PageScaffold(
      title: _isEditing ? 'Edit Routine' : 'New Routine',
      leading: RA_AppBarIconButton(
        icon: Icons.close,
        tooltip: 'Close',
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        RA_DialogButton(
          'Save',
          () => unawaited(_save()),
          color: RA_ColourStyles.secondary,
          style: RA_TextStyles.mediumFont,
        ),
      ],
      body: SingleChildScrollView(
        padding: RA_ShapeStyles.bodyPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KeyedSubtree(
              key: _nameFieldKey,
              child: RA_TextField(
                controller: _nameController,
                focusNode: _nameFocusNode,
                autofocus: !_isEditing,
                label: 'Name',
                placeholder: 'e.g. Morning Medication',
                errorText: _nameError,
                onChanged: (_) {
                  if (_showValidationErrors) setState(() {});
                },
              ),
            ),
            const SizedBox(height: RA_ShapeStyles.space24),
            RA_FormSection(
              label: 'Alarm sound',
              child: Column(
                children: [
                  _highlightTarget(
                    field: RoutineEditFieldEnum.sound,
                    key: _soundFieldKey,
                    child: RA_SoundField(
                      value: _sound,
                      onTap: () => unawaited(_pickSound()),
                    ),
                  ),
                  const SizedBox(height: RA_ShapeStyles.space16),
                  _highlightTarget(
                    field: RoutineEditFieldEnum.volume,
                    key: _volumeFieldKey,
                    child: RA_VolumeField(
                      value: _volume,
                      onChanged: _onVolumeChanged,
                      enabled: !_sound.isSilent,
                    ),
                  ),
                  const SizedBox(height: RA_ShapeStyles.space16),
                  _highlightTarget(
                    field: RoutineEditFieldEnum.fadeIn,
                    key: _fadeInFieldKey,
                    child: Opacity(
                      opacity: _sound.isSilent ? 0.72 : 1,
                      child: IgnorePointer(
                        ignoring: _sound.isSilent,
                        child: RA_Toggle(
                          label: 'Fade in',
                          value: _sound.isSilent ? false : _fadeIn,
                          onChanged: (v) => setState(() => _fadeIn = v),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: RA_ShapeStyles.space16),
                  _highlightTarget(
                    field: RoutineEditFieldEnum.vibrate,
                    key: _vibrateFieldKey,
                    child: RA_Toggle(
                      label: 'Vibrate',
                      value: _vibrate,
                      onChanged: (v) => setState(() => _vibrate = v),
                    ),
                  ),
                  const SizedBox(height: RA_ShapeStyles.space16),
                  RA_Button(
                    text: 'Preview',
                    isPrimary: false,
                    onClick: () => unawaited(_previewAlarm()),
                  ),
                ],
              ),
            ),
            _highlightTarget(
              field: RoutineEditFieldEnum.interval,
              key: _intervalFieldKey,
              child: RA_FormSection(
                label: 'Interval',
                errorText: _intervalError,
                child: RA_DurationField(
                  label: 'Every',
                  value: _interval,
                  hasError: _intervalError != null,
                  onChanged: (v) => setState(() => _interval = v),
                ),
              ),
            ),
            _highlightTarget(
              field: RoutineEditFieldEnum.snooze,
              key: _snoozeFieldKey,
              child: RA_FormSection(
                label: 'Snooze',
                errorText: _snoozeError,
                child: RA_DurationField(
                  label: 'Snooze',
                  value: _snoozeDuration,
                  hasError: _snoozeError != null,
                  onChanged: (v) => setState(() => _snoozeDuration = v),
                ),
              ),
            ),
            RA_FormSection(
              label: 'Daily limit',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _highlightTarget(
                    field: RoutineEditFieldEnum.maxTimesPerDay,
                    key: _maxTimesPerDayFieldKey,
                    child: RA_Toggle(
                      label: 'Max times in a day',
                      value: _maxTimesPerDayEnabled,
                      onChanged: (v) => setState(() {
                        _maxTimesPerDayEnabled = v;
                        if (v && _maxTimesPerDay < 1) {
                          _maxTimesPerDay = 1;
                        }
                      }),
                    ),
                  ),
                  const SizedBox(height: RA_ShapeStyles.space16),
                  _highlightTarget(
                    field: RoutineEditFieldEnum.maxTimesLimit,
                    key: _maxTimesLimitFieldKey,
                    child: RA_NumberField(
                      label: 'Number of times in a day',
                      value: _maxTimesPerDay,
                      onChanged: (v) => setState(() => _maxTimesPerDay = v),
                      min: 1,
                      max: 48,
                      enabled: _maxTimesPerDayEnabled,
                    ),
                  ),
                  const SizedBox(height: RA_ShapeStyles.space16),
                  _highlightTarget(
                    field: RoutineEditFieldEnum.days,
                    key: _daysFieldKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RA_SectionLabel('Enabled on Days'),
                        const SizedBox(height: RA_ShapeStyles.space8),
                        RA_WeekdayField(
                          value: _enabledWeekdays,
                          onChanged: (v) => setState(() {
                            _enabledWeekdays = _normalizeEnabledWeekdays(v);
                          }),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: RA_ShapeStyles.space16),
                  _highlightTarget(
                    field: RoutineEditFieldEnum.dayStart,
                    key: _dayStartFieldKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RA_SectionLabel('Day Start Time'),
                        const SizedBox(height: RA_ShapeStyles.space8),
                        RA_TimeOfDayField(
                          pickerTitle: 'Day Start Time',
                          value: _dayStart,
                          onChanged: (v) => setState(() => _dayStart = v),
                          enabled: _dayStartEnabled,
                        ),
                        if (_maxTimesPerDayEnabled) ...[
                          const SizedBox(height: RA_ShapeStyles.space8),
                          Text(
                            'If count for today has exceeded, we need to know what time to set the next alarm tomorrow',
                            style: RA_TextStyles.smallFont.copyWith(
                              color: RA_ColourStyles.mutedPrimary,
                            ),
                          ),
                        ],
                        if (_hasDisabledWeekday) ...[
                          const SizedBox(height: RA_ShapeStyles.space8),
                          Text(
                            'When the next alarm would naturally fall on a disabled day, we need to know what time to set the next alarm on the upcoming enabled day.',
                            style: RA_TextStyles.smallFont.copyWith(
                              color: RA_ColourStyles.mutedPrimary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _highlightTarget(
              field: RoutineEditFieldEnum.driftCompensation,
              key: _driftCompensationFieldKey,
              child: RA_FormSection(
                label: 'Drift Compensation',
                bottomSpacing: RA_ShapeStyles.space48 + RA_ShapeStyles.space48,
                child: RA_RadioGroup<DriftCompensationTypeCodeEnum>(
                  groupValue: _compensation,
                  onChanged: (v) => setState(() => _compensation = v),
                  options: const [
                    RA_RadioOption(
                      value: DriftCompensationTypeCodeEnum.InitialRing,
                      title: 'Classic Interval',
                    ),
                    RA_RadioOption(
                      value: DriftCompensationTypeCodeEnum.ActualDismissal,
                      title: 'Actual Dismissal',
                      subtitle: 'Next alarm based on when you dismiss',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Soft sage wash that appears instantly, then eases out when [active] clears.
class _FieldFocusHighlight extends StatelessWidget {
  final bool active;
  final Widget child;

  const _FieldFocusHighlight({required this.active, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: active ? Duration.zero : const Duration(milliseconds: 1000),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: active
            ? RA_ColourStyles.secondary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: RA_ShapeStyles.largeBorderRadius,
        boxShadow: active ? RA_ShapeStyles.tealGlow : null,
      ),
      child: child,
    );
  }
}
