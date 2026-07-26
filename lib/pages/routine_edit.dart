import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/components/common/form_section.dart';
import 'package:rolling_alarm/components/common/page_scaffold.dart';
import 'package:rolling_alarm/components/field/duration_field.dart';
import 'package:rolling_alarm/components/field/number_field.dart';
import 'package:rolling_alarm/components/field/radio_group.dart';
import 'package:rolling_alarm/components/field/sound_field.dart';
import 'package:rolling_alarm/components/field/text_field.dart';
import 'package:rolling_alarm/components/field/time_of_day_field.dart';
import 'package:rolling_alarm/components/field/toggle.dart';
import 'package:rolling_alarm/components/field/volume_field.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';
import 'package:rolling_alarm/models/alarm_sound.dart';
import 'package:rolling_alarm/navigation/routes.dart';
import 'package:rolling_alarm/pages/alarm_sound_picker.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/daily_ring_limit.dart';
import 'package:rolling_alarm/services/widget.dart';
import 'package:rolling_alarm/styles.dart';

class RoutineEditPage extends ConsumerStatefulWidget {
  final String dbPath;
  final RoutineModel? existingRoutine;

  const RoutineEditPage({
    super.key,
    required this.dbPath,
    this.existingRoutine,
  });

  @override
  ConsumerState<RoutineEditPage> createState() => _RoutineEditPageState();
}

class _RoutineEditPageState extends ConsumerState<RoutineEditPage> {
  late TextEditingController _nameController;
  Duration _interval = const Duration(hours: 2, minutes: 30);
  Duration _snoozeDuration = const Duration(minutes: 5);
  bool _maxTimesPerDayEnabled = false;
  int _maxTimesPerDay = 1;
  TimeOfDay _dayStart = const TimeOfDay(hour: 0, minute: 0);
  DriftCompensationTypeCodeEnum _compensation =
      DriftCompensationTypeCodeEnum.ActualDismissal;
  RA_AlarmSound _sound = RA_AlarmSound.deviceDefault;
  bool _vibrate = true;
  int _volume = 100;
  bool _fadeIn = false;
  bool _showValidationErrors = false;
  bool _pinToWidget = false;

  final GlobalKey _nameFieldKey = GlobalKey();
  final GlobalKey _intervalFieldKey = GlobalKey();
  final GlobalKey _snoozeFieldKey = GlobalKey();

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
      _compensation =
          DriftCompensationTypeCodeEnum.values[r.DriftCompensationTypeCode];
      _sound = RA_AlarmSound.decode(r.AudioUri);
      _vibrate = r.Vibrate;
      _volume = r.Volume.clamp(0, 100);
      _fadeIn = r.FadeIn;
      unawaited(_loadPinState(r.Id));
    } else {
      unawaited(_seedVolumeFromSystem());
    }
  }

  Future<void> _loadPinState(int routineId) async {
    final pinned = await RA_WidgetService.getPinnedRoutineId();
    if (!mounted) return;
    setState(() => _pinToWidget = pinned == routineId);
  }

  /// Seeds a new routine's slider from the live STREAM_ALARM hardware level.
  Future<void> _seedVolumeFromSystem() async {
    final ratio = await RA_AlarmService.getSystemAlarmVolume();
    if (!mounted) return;
    setState(() => _volume = (ratio * 100).round().clamp(0, 100));
  }

  void _onVolumeChanged(int value) {
    final clamped = value.clamp(0, 100);
    setState(() => _volume = clamped);
    unawaited(RA_AlarmService.setSystemAlarmVolume(clamped / 100.0));
  }

  @override
  void dispose() {
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
      DriftCompensationTypeCode: Value(_compensation.index),
      ShowPreview: const Value(true),
      Vibrate: Value(_vibrate),
      Volume: Value(_volume.clamp(0, 100)),
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
        // cycle. If we were waiting on "Start at time of day" and that time
        // changed, retarget the countdown to the new day-start boundary.
        var next = previousNext;
        if (next != null &&
            oldDayStart != newDayStart &&
            RA_DailyRingLimit.isScheduledAtNextPeriodStart(
              nextTrigger: next,
              dayStartSeconds: oldDayStart,
            )) {
          next = RA_DailyRingLimit.nextPeriodStartAfter(
            DateTime.now(),
            newDayStart,
          );
          await db.updateRoutineState(
            id,
            RoutineStatesCompanion(NextTriggerTime: Value(next)),
          );
        }

        if (next != null) {
          await RA_AlarmService.scheduleNext(
            routineId: id,
            triggerTime: next,
            dbPath: widget.dbPath,
            routineName: name,
            refreshWidget: false,
          );
        }
        await _applyWidgetPin(id, db);
      } else {
        final nextTrigger = DateTime.now().add(_interval);
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
        await _applyWidgetPin(routineId, db);
      }

      if (mounted) Navigator.pop(context);
    } catch (_) {
      // Persist / schedule failures still leave the editor.
      if (mounted) Navigator.pop(context);
    }
  }

  /// Pins or unpins this routine as the single home widget dashboard source.
  Future<void> _applyWidgetPin(int routineId, RA_Database db) async {
    final current = await RA_WidgetService.getPinnedRoutineId();
    if (_pinToWidget) {
      await RA_WidgetService.setPinnedRoutineId(routineId);
    } else if (current == routineId) {
      await RA_WidgetService.setPinnedRoutineId(null);
    }
    await RA_WidgetService.updateWidgetState(db: db);
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
                  RA_SoundField(
                    value: _sound,
                    onTap: () => unawaited(_pickSound()),
                  ),
                  const SizedBox(height: RA_ShapeStyles.space16),
                  RA_VolumeField(
                    value: _volume,
                    onChanged: _onVolumeChanged,
                    enabled: !_sound.isSilent,
                  ),
                  const SizedBox(height: RA_ShapeStyles.space16),
                  Opacity(
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
                  const SizedBox(height: RA_ShapeStyles.space16),
                  RA_Toggle(
                    label: 'Vibrate',
                    value: _vibrate,
                    onChanged: (v) => setState(() => _vibrate = v),
                  ),
                ],
              ),
            ),
            KeyedSubtree(
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
            KeyedSubtree(
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
                  RA_Toggle(
                    label: 'Max times in a day',
                    value: _maxTimesPerDayEnabled,
                    onChanged: (v) => setState(() {
                      _maxTimesPerDayEnabled = v;
                      if (v && _maxTimesPerDay < 1) {
                        _maxTimesPerDay = 1;
                      }
                    }),
                  ),
                  const SizedBox(height: RA_ShapeStyles.space16),
                  RA_NumberField(
                    label: 'Number of times in a day',
                    value: _maxTimesPerDay,
                    onChanged: (v) => setState(() => _maxTimesPerDay = v),
                    min: 1,
                    max: 48,
                    enabled: _maxTimesPerDayEnabled,
                  ),
                  const SizedBox(height: RA_ShapeStyles.space16),
                  RA_TimeOfDayField(
                    label: 'Start at time of day',
                    value: _dayStart,
                    onChanged: (v) => setState(() => _dayStart = v),
                    enabled: _maxTimesPerDayEnabled,
                  ),
                ],
              ),
            ),
            RA_FormSection(
              label: 'Home widget',
              child: RA_Toggle(
                label: 'Show on home widget',
                value: _pinToWidget,
                onChanged: (v) => setState(() => _pinToWidget = v),
              ),
            ),
            RA_FormSection(
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
          ],
        ),
      ),
    );
  }
}
