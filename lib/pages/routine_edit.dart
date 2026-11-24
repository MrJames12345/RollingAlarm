import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/components/common/delete_routine_dialog.dart';
import 'package:rolling_alarm/components/common/form_section.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/page_scaffold.dart';
import 'package:rolling_alarm/components/common/press_scale.dart';
import 'package:rolling_alarm/components/common/pro_badge.dart';
import 'package:rolling_alarm/components/common/section_label.dart';
import 'package:rolling_alarm/components/common/unsaved_changes_dialog.dart';
import 'package:rolling_alarm/components/field/duration_field.dart';
import 'package:rolling_alarm/components/field/number_field.dart';
import 'package:rolling_alarm/components/field/radio_group.dart';
import 'package:rolling_alarm/components/field/sound_field.dart';
import 'package:rolling_alarm/components/field/text_field.dart';
import 'package:rolling_alarm/components/field/time_of_day_field.dart';
import 'package:rolling_alarm/components/field/toggle.dart';
import 'package:rolling_alarm/components/field/volume_field.dart';
import 'package:rolling_alarm/components/field/weekday_field.dart';
import 'package:rolling_alarm/components/routine/quick_templates_strip.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';
import 'package:rolling_alarm/enums/log_action_type_code.dart';
import 'package:rolling_alarm/enums/routine_edit_field.dart';
import 'package:rolling_alarm/models/alarm_sound.dart';
import 'package:rolling_alarm/models/routine_template.dart';
import 'package:rolling_alarm/navigation/routes.dart';
import 'package:rolling_alarm/pages/alarm_ring.dart';
import 'package:rolling_alarm/pages/alarm_sound_picker.dart';
import 'package:rolling_alarm/pages/paywall.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/daily_ring_limit.dart';
import 'package:rolling_alarm/services/permissions.dart';
import 'package:rolling_alarm/services/purchase.dart';
import 'package:rolling_alarm/services/routine_duplicate.dart';
import 'package:rolling_alarm/services/swing_roster.dart';
import 'package:rolling_alarm/services/weekday_schedule.dart';
import 'package:rolling_alarm/services/widget.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:rolling_alarm/utils.dart';

class RoutineEditPage extends ConsumerStatefulWidget {
  final String dbPath;
  final RoutineModel? existingRoutine;

  /// When set, scrolls to this field after open and briefly highlights it.
  final RoutineEditFieldEnum? scrollToField;

  /// Optional 1-tap quick-start template to prefill a new routine.
  final RA_RoutineTemplate? initialTemplate;

  const RoutineEditPage({
    super.key,
    required this.dbPath,
    this.existingRoutine,
    this.scrollToField,
    this.initialTemplate,
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
  bool _swingCycleEnabled = false;
  int _cycleOnDays = 8;
  int _cycleOffDays = 6;
  late DateTime _cycleAnchorDate;
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
  final GlobalKey _swingRosterFieldKey = GlobalKey();

  RoutineEditFieldEnum? _highlightedField;
  String? _selectedTemplateId;
  bool _saving = false;
  bool _wasDirty = false;

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

  bool get _hasSwingWeekdayConflict =>
      _swingCycleEnabled &&
      !RA_SwingRosterSchedule.hasIntersectingActiveDay(
        cycleOnDays: _cycleOnDays,
        cycleOffDays: _cycleOffDays,
        cycleAnchorEpochDay: _effectiveCycleAnchorEpochDay,
        enabledWeekdays: _enabledWeekdays,
      );

  String? get _swingConflictError => _hasSwingWeekdayConflict
      ? 'No calendar day matches both this swing cycle and the enabled weekdays.'
      : null;

  /// First invalid required field key, in form order.
  GlobalKey? get _firstInvalidFieldKey {
    if (_nameError != null) return _nameFieldKey;
    if (_intervalError != null) return _intervalFieldKey;
    if (_snoozeError != null) return _snoozeFieldKey;
    if (_swingConflictError != null) return _swingRosterFieldKey;
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
    RoutineEditFieldEnum.swingRoster => _swingRosterFieldKey,
  };

  DateTime _todayLocalDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  int get _effectiveCycleOnDays => _swingCycleEnabled ? _cycleOnDays : 0;

  int get _effectiveCycleOffDays => _swingCycleEnabled ? _cycleOffDays : 0;

  int? get _effectiveCycleAnchorEpochDay => _swingCycleEnabled
      ? RA_SwingRosterSchedule.localEpochDay(_cycleAnchorDate)
      : null;

  /// Keeps edit state on [allDaysMask], never raw `0`, so Day Start enablement
  /// does not flicker between 0 and 127 when meaning "every day."
  int _normalizeEnabledWeekdays(int mask) =>
      RA_WeekdaySchedule.effectiveMask(mask);

  bool get _hasDisabledWeekday =>
      !RA_WeekdaySchedule.isEveryDay(_enabledWeekdays);

  bool get _dayStartEnabled =>
      _maxTimesPerDayEnabled || _hasDisabledWeekday || _swingCycleEnabled;

  /// True when editing and the form differs from the persisted routine.
  bool get _hasUnsavedChanges {
    final r = widget.existingRoutine;
    if (r == null) return false;

    final dayStartSeconds = RA_DailyRingLimit.normalizeDayStartSeconds(
      _dayStart.hour * 3600 + _dayStart.minute * 60,
    );
    final existingDayStart = RA_DailyRingLimit.normalizeDayStartSeconds(
      r.DayStartSeconds,
    );
    final existingMaxTimes = r.MaxTimesPerDay < 1 ? 1 : r.MaxTimesPerDay;
    final existingVolume = r.Volume.clamp(5, 100);
    final existingSoundEncode = RA_AlarmSound.decode(r.AudioUri).encode();
    final existingSwingEnabled = RA_SwingRosterSchedule.isActive(
      cycleOnDays: r.CycleOnDays,
      cycleOffDays: r.CycleOffDays,
      cycleAnchorEpochDay: r.CycleAnchorEpochDay,
    );

    return _nameController.text.trim() != r.Name ||
        _interval.inSeconds != r.IntervalSeconds ||
        _snoozeDuration.inSeconds != r.SnoozeSeconds ||
        _maxTimesPerDayEnabled != r.MaxTimesPerDayEnabled ||
        _maxTimesPerDay != existingMaxTimes ||
        dayStartSeconds != existingDayStart ||
        _enabledWeekdays != _normalizeEnabledWeekdays(r.EnabledWeekdays) ||
        _swingCycleEnabled != existingSwingEnabled ||
        (_swingCycleEnabled &&
            (_cycleOnDays != r.CycleOnDays ||
                _cycleOffDays != r.CycleOffDays ||
                _effectiveCycleAnchorEpochDay != r.CycleAnchorEpochDay)) ||
        _compensation.index != r.DriftCompensationTypeCode ||
        _vibrate != r.Vibrate ||
        _volume.clamp(5, 100) != existingVolume ||
        _fadeIn != r.FadeIn ||
        _sound.encode() != existingSoundEncode;
  }

  @override
  void initState() {
    super.initState();
    _cycleAnchorDate = _todayLocalDate();
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
      final hasSwing = RA_SwingRosterSchedule.isActive(
        cycleOnDays: r.CycleOnDays,
        cycleOffDays: r.CycleOffDays,
        cycleAnchorEpochDay: r.CycleAnchorEpochDay,
      );
      _swingCycleEnabled = hasSwing;
      if (hasSwing) {
        _cycleOnDays = r.CycleOnDays.clamp(
          RA_SwingRosterSchedule.minCycleDays,
          RA_SwingRosterSchedule.maxCycleDays,
        );
        _cycleOffDays = r.CycleOffDays.clamp(
          RA_SwingRosterSchedule.minCycleDays,
          RA_SwingRosterSchedule.maxCycleDays,
        );
        _cycleAnchorDate = RA_SwingRosterSchedule.dateFromEpochDay(
          r.CycleAnchorEpochDay!,
        );
      }
      _compensation =
          DriftCompensationTypeCodeEnum.values[r.DriftCompensationTypeCode];
      _sound = RA_AlarmSound.decode(r.AudioUri);
      _vibrate = r.Vibrate;
      _volume = r.Volume.clamp(5, 100);
      _fadeIn = r.FadeIn;
    } else {
      unawaited(RA_AlarmService.setSystemAlarmVolume(0.5));
      final initialTemplate = widget.initialTemplate;
      if (initialTemplate != null) {
        final isPro = ref.read(IsProProvider);
        _applyTemplateFields(initialTemplate, isPro: isPro);
        if (initialTemplate.usesProDriftMode && !isPro) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _showTemplateProDriftSnackBar();
          });
        } else if (initialTemplate.usesProSwingCycle && !isPro) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _showTemplateProSwingSnackBar(initialTemplate);
          });
        }
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _focusNameField());
      }
    }

    final scrollTo = widget.scrollToField;
    if (scrollTo != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_scrollToAndHighlight(scrollTo));
      });
    }
  }

  void _applyTemplateFields(
    RA_RoutineTemplate template, {
    required bool isPro,
  }) {
    _selectedTemplateId = template.id;
    _nameController.text = template.routineName;
    _interval = template.interval;
    _snoozeDuration = template.snooze;
    _maxTimesPerDayEnabled = template.maxTimesPerDayEnabled;
    _maxTimesPerDay = template.maxTimesPerDay;
    _dayStart = template.dayStart;
    _enabledWeekdays = _normalizeEnabledWeekdays(template.enabledWeekdays);
    if (template.hasSwingCycle) {
      final cycle = template.effectiveSwingCycle(isPro: isPro);
      _swingCycleEnabled = true;
      _cycleOnDays = cycle.onDays;
      _cycleOffDays = cycle.offDays;
      _cycleAnchorDate = _todayLocalDate();
    } else {
      _swingCycleEnabled = false;
    }
    _compensation = template.effectiveCompensation(isPro: isPro);
    _showValidationErrors = false;
  }

  void _onSelectTemplate(RA_RoutineTemplate template) {
    final isPro = ref.read(IsProProvider);
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _applyTemplateFields(template, isPro: isPro);
    });
    if (template.usesProDriftMode && !isPro && mounted) {
      _showTemplateProDriftSnackBar();
    } else if (template.usesProSwingCycle && !isPro && mounted) {
      _showTemplateProSwingSnackBar(template);
    }
  }

  void _showTemplateProSwingSnackBar(RA_RoutineTemplate template) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: RA_ColourStyles.surface,
        shape: RoundedRectangleBorder(
          borderRadius: RA_ShapeStyles.largeBorderRadius,
          side: BorderSide(color: RA_ShapeStyles.idleSurfaceBorder),
        ),
        content: Text(
          'Applied with free 8/6 Swing. Unlock Pro for ${template.cycleOnDays}/${template.cycleOffDays} & custom rosters.',
          style: RA_TextStyles.tinyFont,
        ),
        action: SnackBarAction(
          label: 'Unlock',
          textColor: RA_ColourStyles.secondary,
          onPressed: () => unawaited(
            _unlockCustomSwingCycle(
              targetOnDays: template.cycleOnDays,
              targetOffDays: template.cycleOffDays,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _unlockCustomSwingCycle({
    required int targetOnDays,
    required int targetOffDays,
  }) async {
    final unlocked = await PaywallPage.show(
      context,
      featureTrigger:
          'Customize swing roster cycles (2/1, 2/2 & custom N/M) with Pro',
    );
    if (unlocked && mounted) {
      setState(() {
        _swingCycleEnabled = true;
        _cycleOnDays = targetOnDays.clamp(
          RA_SwingRosterSchedule.minCycleDays,
          RA_SwingRosterSchedule.maxCycleDays,
        );
        _cycleOffDays = targetOffDays.clamp(
          RA_SwingRosterSchedule.minCycleDays,
          RA_SwingRosterSchedule.maxCycleDays,
        );
      });
    }
  }

  Future<void> _selectSwingPreset(RA_SwingRosterPreset preset) async {
    if (preset.requiresPro && !ref.read(IsProProvider)) {
      await _unlockCustomSwingCycle(
        targetOnDays: preset.onDays,
        targetOffDays: preset.offDays,
      );
      return;
    }
    setState(() {
      _swingCycleEnabled = true;
      _cycleOnDays = preset.onDays;
      _cycleOffDays = preset.offDays;
    });
  }

  Future<void> _changeCustomSwingDays({int? onDays, int? offDays}) async {
    final nextOn = (onDays ?? _cycleOnDays).clamp(
      RA_SwingRosterSchedule.minCycleDays,
      RA_SwingRosterSchedule.maxCycleDays,
    );
    final nextOff = (offDays ?? _cycleOffDays).clamp(
      RA_SwingRosterSchedule.minCycleDays,
      RA_SwingRosterSchedule.maxCycleDays,
    );
    if (!ref.read(IsProProvider) &&
        !RA_SwingRosterSchedule.isFreeCyclePair(
          cycleOnDays: nextOn,
          cycleOffDays: nextOff,
        )) {
      await _unlockCustomSwingCycle(
        targetOnDays: nextOn,
        targetOffDays: nextOff,
      );
      return;
    }
    setState(() {
      _cycleOnDays = nextOn;
      _cycleOffDays = nextOff;
    });
  }

  Future<void> _pickSwingAnchorDate() async {
    RA_Haptics.heavyUnawaited();
    final now = _todayLocalDate();
    final minDate = DateTime(now.year - 2, 1, 1);
    final maxDate = DateTime(now.year + 5, 12, 31);
    final firstDate = _cycleAnchorDate.isBefore(minDate)
        ? _cycleAnchorDate
        : minDate;
    final lastDate = _cycleAnchorDate.isAfter(maxDate)
        ? _cycleAnchorDate
        : maxDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: _cycleAnchorDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Day 1 of ON Swing',
    );
    if (picked != null && mounted) {
      setState(() {
        _cycleAnchorDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  void _showTemplateProDriftSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: RA_ColourStyles.surface,
        shape: RoundedRectangleBorder(
          borderRadius: RA_ShapeStyles.largeBorderRadius,
          side: BorderSide(color: RA_ShapeStyles.idleSurfaceBorder),
        ),
        content: Text(
          'Applied with Actual Dismissal. Unlock Pro for Classic Interval grid.',
          style: RA_TextStyles.tinyFont,
        ),
        action: SnackBarAction(
          label: 'Unlock',
          textColor: RA_ColourStyles.secondary,
          onPressed: () => unawaited(_unlockInitialRing()),
        ),
      ),
    );
  }

  Future<void> _onToggleFadeIn(bool nextValue) async {
    if (nextValue && !ref.read(IsProProvider)) {
      final unlocked = await PaywallPage.show(
        context,
        featureTrigger: 'Unlock gentle alarm Fade-In with Pro',
      );
      if (!unlocked || !mounted) return;
    }
    setState(() => _fadeIn = nextValue);
  }

  Future<void> _onSelectCompensation(DriftCompensationTypeCodeEnum next) async {
    if (next == _compensation) return;
    if (next == DriftCompensationTypeCodeEnum.InitialRing &&
        !ref.read(IsProProvider)) {
      await _unlockInitialRing();
      return;
    }
    setState(() => _compensation = next);
  }

  Future<void> _unlockInitialRing() async {
    final unlocked = await PaywallPage.show(
      context,
      featureTrigger: 'Unlock Initial Ring Drift Compensation',
    );
    if (unlocked && mounted) {
      setState(() => _compensation = DriftCompensationTypeCodeEnum.InitialRing);
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
      CycleOnDays: Value(_effectiveCycleOnDays),
      CycleOffDays: Value(_effectiveCycleOffDays),
      CycleAnchorEpochDay: Value(_effectiveCycleAnchorEpochDay),
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

  /// Writes form values to the DB. Returns the saved row, or null on
  /// validation failure. Throws on persist / schedule errors.
  Future<RoutineModel?> _persistRoutine() async {
    setState(() => _showValidationErrors = true);
    final invalidKey = _firstInvalidFieldKey;
    if (invalidKey != null) {
      unawaited(_scrollToField(invalidKey));
      return null;
    }

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
      await db.insertActivityLog(
        routineId: id,
        action: LogActionTypeCodeEnum.Edit,
      );

      // Keep the active timer as-is so interval / other edits apply next
      // cycle. Retarget when day-start changes while waiting on that
      // boundary, or when the daily cap crosses today's count.
      final now = DateTime.now();
      final samePeriod =
          state?.TimesRingDay != null &&
          RA_DailyRingLimit.isSamePeriod(
            state!.TimesRingDay!,
            now,
            oldDayStart,
          );
      final effectiveExtra = samePeriod ? state.ExtraMaxTimesToday : 0;
      final next = RA_DailyRingLimit.retargetNextAfterEdit(
        previousNext: previousNext,
        oldDayStartSeconds: oldDayStart,
        newDayStartSeconds: newDayStart,
        oldMaxTimesPerDayEnabled: existing.MaxTimesPerDayEnabled,
        newMaxTimesPerDayEnabled: _maxTimesPerDayEnabled,
        oldMaxTimesPerDay: existing.MaxTimesPerDay,
        newMaxTimesPerDay: _maxTimesPerDay,
        oldExtraMaxTimesToday: effectiveExtra,
        newExtraMaxTimesToday: effectiveExtra,
        timesRingToday: state?.TimesRingToday ?? 0,
        timesRingDay: state?.TimesRingDay,
        now: now,
        intervalSeconds: _interval.inSeconds,
        enabledWeekdays: _enabledWeekdays,
        oldCycleOnDays: existing.CycleOnDays,
        newCycleOnDays: _effectiveCycleOnDays,
        oldCycleOffDays: existing.CycleOffDays,
        newCycleOffDays: _effectiveCycleOffDays,
        oldCycleAnchorEpochDay: existing.CycleAnchorEpochDay,
        newCycleAnchorEpochDay: _effectiveCycleAnchorEpochDay,
      );
      final savedRoutine = await db.getRoutineById(id);
      if (next != null) {
        if (previousNext == null ||
            next.millisecondsSinceEpoch !=
                previousNext.millisecondsSinceEpoch) {
          await db.updateRoutineState(
            id,
            RoutineStatesCompanion(NextTriggerTime: Value(next)),
          );
        }
        if (savedRoutine.IsActive && state?.PausedAt == null) {
          await RA_AlarmService.scheduleNext(
            routineId: id,
            triggerTime: next,
            dbPath: widget.dbPath,
            routineName: name,
            routine: savedRoutine,
            state: state?.copyWith(NextTriggerTime: Value(next)),
            refreshWidget: false,
          );
        }
      }
      await RA_WidgetService.updateWidgetState(db: db);
      return savedRoutine;
    }

    if (!_isEditing && !ref.read(IsProProvider)) {
      final liveCount = await db.countLiveRoutines();
      if (liveCount >= RA_PurchaseService.freeRoutineLimit) {
        if (!mounted) return null;
        final unlocked = await PaywallPage.show(
          context,
          featureTrigger: 'Create unlimited rolling routines with Pro',
        );
        if (!unlocked || !mounted) return null;
      }
    }

    final dayStartSeconds = RA_DailyRingLimit.normalizeDayStartSeconds(
      _dayStart.hour * 3600 + _dayStart.minute * 60,
    );
    final nextTrigger = RA_DailyRingLimit.initialTriggerTime(
      now: DateTime.now(),
      interval: _interval,
      maxTimesPerDayEnabled: _maxTimesPerDayEnabled,
      dayStartSeconds: dayStartSeconds,
      enabledWeekdays: _enabledWeekdays,
      cycleOnDays: _effectiveCycleOnDays,
      cycleOffDays: _effectiveCycleOffDays,
      cycleAnchorEpochDay: _effectiveCycleAnchorEpochDay,
    );
    final routineId = await db.insertRoutineWithInitialState(
      routine: _companion(),
      nextTriggerTime: nextTrigger,
    );
    final createdRoutine = await db.getRoutineById(routineId);
    final createdState = await db.getRoutineState(routineId);
    await RA_AlarmService.scheduleNext(
      routineId: routineId,
      triggerTime: nextTrigger,
      dbPath: widget.dbPath,
      routineName: name,
      routine: createdRoutine,
      state: createdState,
      refreshWidget: false,
    );
    await RA_WidgetService.updateWidgetState(db: db);
    return createdRoutine;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final saved = await _persistRoutine();
      if (saved != null && mounted) {
        await RA_PermissionService.ensureCoreAlarmPermissions(context);
        if (mounted) Navigator.pop(context);
      }
    } catch (_) {
      // Persist / schedule failures still leave the editor.
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      } else {
        _saving = false;
      }
    }
  }

  Future<void> _handleExit() async {
    if (_saving) return;
    if (!_hasUnsavedChanges) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final name = widget.existingRoutine?.Name.trim();
    final choice = await RA_showUnsavedChangesDialog(
      context,
      routineName: (name != null && name.isNotEmpty) ? name : 'this routine',
    );
    if (choice == null || !mounted) return;
    if (choice == RA_UnsavedChangesChoice.saveAndContinue) {
      await _save();
      return;
    }
    if (mounted) Navigator.pop(context);
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
    ref.watch(AppThemeModeProvider);
    final isPro = ref.watch(IsProProvider);
    final showInitialRingProBadge =
        !isPro && _compensation != DriftCompensationTypeCodeEnum.InitialRing;
    final hasUnsavedChanges = _hasUnsavedChanges;
    _wasDirty = hasUnsavedChanges;

    return PopScope(
      canPop: !hasUnsavedChanges && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_handleExit());
      },
      child: RA_PageScaffold(
        title: _isEditing ? 'Edit Routine' : 'New Routine',
        leading: RA_AppBarIconButton(
          icon: Icons.close,
          tooltip: 'Close',
          onPressed: () => unawaited(_handleExit()),
        ),
        actions: [
          RA_DialogButton(
            'Save',
            () => unawaited(_save()),
            color: RA_ColourStyles.secondary,
          ),
        ],
        body: SingleChildScrollView(
          padding: RA_ShapeStyles.bodyPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_isEditing) ...[
                RA_QuickTemplatesStrip(
                  selectedTemplateId: _selectedTemplateId,
                  onSelect: _onSelectTemplate,
                ),
                const SizedBox(height: RA_ShapeStyles.space24),
              ],
              KeyedSubtree(
                key: _nameFieldKey,
                child: RA_TextField(
                  controller: _nameController,
                  focusNode: _nameFocusNode,
                  autofocus: !_isEditing && widget.initialTemplate == null,
                  label: 'Name',
                  placeholder: 'e.g. Morning Medication',
                  errorText: _nameError,
                  onChanged: (_) {
                    final dirty = _hasUnsavedChanges;
                    if (_showValidationErrors || dirty != _wasDirty) {
                      _wasDirty = dirty;
                      setState(() {});
                    }
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
                          trailingBadge:
                              !isPro && !_fadeIn ? const RA_ProBadge() : null,
                          onChanged: (v) => unawaited(_onToggleFadeIn(v)),
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
                    field: RoutineEditFieldEnum.swingRoster,
                    key: _swingRosterFieldKey,
                    child: _SwingRosterEditorBlock(
                      enabled: _swingCycleEnabled,
                      isPro: isPro,
                      cycleOnDays: _cycleOnDays,
                      cycleOffDays: _cycleOffDays,
                      anchorDate: _cycleAnchorDate,
                      dayStartSeconds: RA_DailyRingLimit.normalizeDayStartSeconds(
                        _dayStart.hour * 3600 + _dayStart.minute * 60,
                      ),
                      enabledWeekdays: _enabledWeekdays,
                      conflictError: _swingConflictError,
                      onToggle: (v) => setState(() => _swingCycleEnabled = v),
                      onSelectPreset: (preset) =>
                          unawaited(_selectSwingPreset(preset)),
                      onChangeOnDays: (v) =>
                          unawaited(_changeCustomSwingDays(onDays: v)),
                      onChangeOffDays: (v) =>
                          unawaited(_changeCustomSwingDays(offDays: v)),
                      onPickAnchorDate: () => unawaited(_pickSwingAnchorDate()),
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
                            'If count for today has exceeded, we need to know what time to set the next alarm tomorrow.',
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
                        if (_swingCycleEnabled) ...[
                          const SizedBox(height: RA_ShapeStyles.space8),
                          Text(
                            'When returning from R&R off-swing days, alarms resume cleanly at this Day Start Time.',
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
                bottomSpacing: _isEditing
                    ? RA_ShapeStyles.space24
                    : RA_ShapeStyles.space48 + RA_ShapeStyles.space48,
                child: RA_RadioGroup<DriftCompensationTypeCodeEnum>(
                  groupValue: _compensation,
                  onChanged: (v) => unawaited(_onSelectCompensation(v)),
                  options: [
                    RA_RadioOption(
                      value: DriftCompensationTypeCodeEnum.InitialRing,
                      title: 'Classic Interval',
                      trailing: showInitialRingProBadge
                          ? const RA_ProBadge()
                          : null,
                    ),
                    const RA_RadioOption(
                      value: DriftCompensationTypeCodeEnum.ActualDismissal,
                      title: 'Actual Dismissal',
                      subtitle: 'Next alarm based on when you dismiss',
                    ),
                  ],
                ),
              ),
            ),
            if (_isEditing) ...[
              RA_Button(
                text: 'Duplicate',
                onClick: () => unawaited(_duplicateRoutine()),
              ),
              const SizedBox(height: RA_ShapeStyles.space16),
              RA_Button(
                text: 'Delete',
                backgroundColor: RA_ColourStyles.softCoral,
                foregroundColor: RA_ColourStyles.onAccent,
                shadowColor: RA_ColourStyles.softCoral.withValues(alpha: 0.35),
                onClick: () => unawaited(_deleteRoutine()),
              ),
              const SizedBox(
                height: RA_ShapeStyles.space48 + RA_ShapeStyles.space48,
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }

  Future<void> _duplicateRoutine() async {
    final existing = widget.existingRoutine;
    if (existing == null) return;

    if (!ref.read(IsProProvider)) {
      final db = ref.read(RA_DatabaseProvider);
      final liveCount = await db.countLiveRoutines();
      if (!mounted) return;
      if (liveCount >= RA_PurchaseService.freeRoutineLimit) {
        final unlocked = await PaywallPage.show(
          context,
          featureTrigger: 'Create unlimited rolling routines with Pro',
        );
        if (!unlocked || !mounted) return;
      }
    }

    var source = existing;
    if (_hasUnsavedChanges) {
      final choice = await RA_showUnsavedChangesDialog(
        context,
        routineName: existing.Name,
      );
      if (choice == null || !mounted) return;

      if (choice == RA_UnsavedChangesChoice.saveAndContinue) {
        try {
          final saved = await _persistRoutine();
          if (saved == null || !mounted) return;
          source = saved;
        } catch (_) {
          return;
        }
      }
    }

    RA_Haptics.heavyUnawaited();
    final newId = await RA_tryAsync(() async {
      final db = ref.read(RA_DatabaseProvider);
      return RA_RoutineDuplicateService.duplicate(
        db: db,
        source: source,
        dbPath: widget.dbPath,
      );
    });
    if (newId == null || !mounted) return;

    await RA_PermissionService.ensureCoreAlarmPermissions(context);
    if (!mounted) return;

    final db = ref.read(RA_DatabaseProvider);
    final copy = await db.getRoutineById(newId);
    if (!mounted) return;
    await Navigator.pushReplacement(
      context,
      RA_Routes.fade(
        RoutineEditPage(dbPath: widget.dbPath, existingRoutine: copy),
      ),
    );
  }

  Future<void> _deleteRoutine() async {
    final existing = widget.existingRoutine;
    if (existing == null) return;

    final confirmed = await RA_showDeleteRoutineDialog(
      context,
      routineName: existing.Name,
    );
    if (confirmed != true) return;

    final deleted = await RA_tryAsync(() async {
      final db = ref.read(RA_DatabaseProvider);
      await RA_AlarmService.cancel(existing.Id);
      await db.softDeleteRoutine(existing.Id);
      await RA_WidgetService.updateWidgetState(db: db);
      return true;
    });
    if (deleted == true && mounted) {
      // Leave edit and any summary underneath so home is showing.
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
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

/// Swing roster cycle toggle, 1-tap FIFO/nursing preset chips, custom N/M
/// steppers, and "Day 1 of Swing" anchor picker.
class _SwingRosterEditorBlock extends StatelessWidget {
  final bool enabled;
  final bool isPro;
  final int cycleOnDays;
  final int cycleOffDays;
  final DateTime anchorDate;
  final int dayStartSeconds;
  final int enabledWeekdays;
  final String? conflictError;
  final ValueChanged<bool> onToggle;
  final ValueChanged<RA_SwingRosterPreset> onSelectPreset;
  final ValueChanged<int> onChangeOnDays;
  final ValueChanged<int> onChangeOffDays;
  final VoidCallback onPickAnchorDate;

  const _SwingRosterEditorBlock({
    required this.enabled,
    required this.isPro,
    required this.cycleOnDays,
    required this.cycleOffDays,
    required this.anchorDate,
    required this.dayStartSeconds,
    required this.enabledWeekdays,
    this.conflictError,
    required this.onToggle,
    required this.onSelectPreset,
    required this.onChangeOnDays,
    required this.onChangeOffDays,
    required this.onPickAnchorDate,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isTodayAnchor =
        anchorDate.year == now.year &&
        anchorDate.month == now.month &&
        anchorDate.day == now.day;
    final anchorLabel = isTodayAnchor
        ? 'Today · ${DateFormat.yMMMd().format(anchorDate)}'
        : DateFormat.yMMMd().format(anchorDate);
    final previewStatus = enabled
        ? RA_SwingRosterSchedule.statusAt(
            now: now,
            cycleOnDays: cycleOnDays,
            cycleOffDays: cycleOffDays,
            cycleAnchorEpochDay: RA_SwingRosterSchedule.localEpochDay(
              anchorDate,
            ),
            dayStartSeconds: dayStartSeconds,
            enabledWeekdays: enabledWeekdays,
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RA_Toggle(
          label: 'Swing Roster Cycle (FIFO / Shift Work)',
          value: enabled,
          onChanged: onToggle,
        ),
        if (enabled) ...[
          const SizedBox(height: RA_ShapeStyles.space16),
          Wrap(
            spacing: RA_ShapeStyles.space8,
            runSpacing: RA_ShapeStyles.space8,
            children: [
              for (final preset in RA_SwingRosterSchedule.presets)
                _SwingPresetChip(
                  preset: preset,
                  selected:
                      cycleOnDays == preset.onDays &&
                      cycleOffDays == preset.offDays,
                  showProBadge: preset.requiresPro && !isPro,
                  onTap: () => onSelectPreset(preset),
                ),
            ],
          ),
          const SizedBox(height: RA_ShapeStyles.space16),
          RA_SectionLabel(
            'Custom Cycle Days',
            trailing: !isPro ? const RA_ProBadge() : null,
          ),
          const SizedBox(height: RA_ShapeStyles.space8),
          RA_NumberFieldRow(
            left: RA_NumberField(
              label: 'Days On',
              value: cycleOnDays,
              min: RA_SwingRosterSchedule.minCycleDays,
              max: RA_SwingRosterSchedule.maxCycleDays,
              onChanged: onChangeOnDays,
            ),
            right: RA_NumberField(
              label: 'Days Off',
              value: cycleOffDays,
              min: RA_SwingRosterSchedule.minCycleDays,
              max: RA_SwingRosterSchedule.maxCycleDays,
              onChanged: onChangeOffDays,
            ),
          ),
          const SizedBox(height: RA_ShapeStyles.space16),
          RA_SectionLabel('Day 1 of Swing'),
          const SizedBox(height: RA_ShapeStyles.space8),
          RA_PressScale(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPickAnchorDate,
                borderRadius: RA_ShapeStyles.largeBorderRadius,
                splashColor: RA_ColourStyles.secondary.withValues(alpha: 0.16),
                highlightColor: RA_ColourStyles.secondary.withValues(
                  alpha: 0.08,
                ),
                child: Ink(
                  decoration: RA_ShapeStyles.elevatedSurface(),
                  child: Padding(
                    padding: const EdgeInsets.all(RA_ShapeStyles.space16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            anchorLabel,
                            style: RA_TextStyles.smallFont.copyWith(
                              color: RA_ColourStyles.valueText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 20,
                          color: RA_ColourStyles.mutedPrimary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (conflictError != null) ...[
            const SizedBox(height: RA_ShapeStyles.space8),
            Text(
              conflictError!,
              style: RA_TextStyles.tinyFont.copyWith(
                color: RA_ColourStyles.readableAccent(
                  RA_ColourStyles.softCoral,
                ),
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else if (previewStatus != null) ...[
            const SizedBox(height: RA_ShapeStyles.space8),
            Text(
              previewStatus.badgeLabel,
              style: RA_TextStyles.tinyFont.copyWith(
                color: RA_ColourStyles.readableAccent(
                  previewStatus.isOnSwing
                      ? RA_ColourStyles.secondary
                      : RA_ColourStyles.pauseOchre,
                ),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _SwingPresetChip extends StatelessWidget {
  final RA_SwingRosterPreset preset;
  final bool selected;
  final bool showProBadge;
  final VoidCallback onTap;

  const _SwingPresetChip({
    required this.preset,
    required this.selected,
    required this.showProBadge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const accent = RA_ColourStyles.secondary;
    return RA_PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            RA_Haptics.heavyUnawaited();
            onTap();
          },
          borderRadius: RA_ShapeStyles.largeBorderRadius,
          splashColor: accent.withValues(alpha: 0.16),
          highlightColor: accent.withValues(alpha: 0.08),
          child: Ink(
            decoration: RA_ShapeStyles.elevatedSurface(
              fill: selected
                  ? Color.alphaBlend(
                      accent.withValues(alpha: 0.14),
                      RA_ColourStyles.surface,
                    )
                  : null,
              borderColor: selected ? accent.withValues(alpha: 0.65) : null,
              borderWidth: selected ? 1.5 : 1,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    preset.label,
                    style: RA_TextStyles.tinyFont.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? RA_ColourStyles.readableAccent(accent)
                          : RA_ColourStyles.primary,
                    ),
                  ),
                  if (showProBadge) ...[
                    const SizedBox(width: 6),
                    const RA_ProBadge(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
