import 'package:flutter/material.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';
import 'package:rolling_alarm/services/weekday_schedule.dart';

/// Curated 1-tap quick-start routine preset to eliminate blank-page friction.
class RA_RoutineTemplate {
  final String id;
  final String title;
  final String routineName;
  final String subtitle;
  final IconData icon;
  final Duration interval;
  final Duration snooze;
  final TimeOfDay dayStart;
  final bool maxTimesPerDayEnabled;
  final int maxTimesPerDay;
  final int enabledWeekdays;
  final DriftCompensationTypeCodeEnum compensation;

  const RA_RoutineTemplate({
    required this.id,
    required this.title,
    required this.routineName,
    required this.subtitle,
    required this.icon,
    required this.interval,
    required this.snooze,
    required this.dayStart,
    required this.maxTimesPerDayEnabled,
    required this.maxTimesPerDay,
    required this.enabledWeekdays,
    required this.compensation,
  });

  /// True when this template defaults to a Pro-gated drift mode.
  bool get usesProDriftMode =>
      compensation == DriftCompensationTypeCodeEnum.InitialRing;

  /// Effective drift compensation given the user's current entitlement.
  DriftCompensationTypeCodeEnum effectiveCompensation({required bool isPro}) {
    if (usesProDriftMode && !isPro) {
      return DriftCompensationTypeCodeEnum.ActualDismissal;
    }
    return compensation;
  }
}

/// Curated Day-0 routine templates for Rolling Alarm.
class RA_RoutineTemplates {
  RA_RoutineTemplates._();

  /// Mon–Fri bitmask (bits 0..4).
  static const int weekdaysMask = 0x1F;

  static const RA_RoutineTemplate medication = RA_RoutineTemplate(
    id: 'medication',
    title: 'Medication Cadence',
    routineName: 'Medication',
    subtitle: 'Every 4h · 4/day · 7:00 AM',
    icon: Icons.medication_outlined,
    interval: Duration(hours: 4),
    snooze: Duration(minutes: 5),
    dayStart: TimeOfDay(hour: 7, minute: 0),
    maxTimesPerDayEnabled: true,
    maxTimesPerDay: 4,
    enabledWeekdays: RA_WeekdaySchedule.allDaysMask,
    compensation: DriftCompensationTypeCodeEnum.ActualDismissal,
  );

  static const RA_RoutineTemplate focusHydration = RA_RoutineTemplate(
    id: 'focus_hydration',
    title: 'Focus / Hydration Grid',
    routineName: 'Focus & Hydration',
    subtitle: 'Every 90m · 8/day · Mon–Fri',
    icon: Icons.water_drop_outlined,
    interval: Duration(hours: 1, minutes: 30),
    snooze: Duration(minutes: 5),
    dayStart: TimeOfDay(hour: 8, minute: 0),
    maxTimesPerDayEnabled: true,
    maxTimesPerDay: 8,
    enabledWeekdays: weekdaysMask,
    compensation: DriftCompensationTypeCodeEnum.InitialRing,
  );

  static const RA_RoutineTemplate nightShiftFifo = RA_RoutineTemplate(
    id: 'night_shift_fifo',
    title: 'WA FIFO / Night Shift',
    routineName: 'Night Shift Turnaround',
    subtitle: 'Every 12h · 1/day · 6:00 PM',
    icon: Icons.nightlight_outlined,
    interval: Duration(hours: 12),
    snooze: Duration(minutes: 10),
    dayStart: TimeOfDay(hour: 18, minute: 0),
    maxTimesPerDayEnabled: true,
    maxTimesPerDay: 1,
    enabledWeekdays: RA_WeekdaySchedule.allDaysMask,
    compensation: DriftCompensationTypeCodeEnum.ActualDismissal,
  );

  static const RA_RoutineTemplate caregiverCheck = RA_RoutineTemplate(
    id: 'caregiver_check',
    title: 'Caregiver / Patient Check',
    routineName: 'Caregiver Check',
    subtitle: 'Every 2h · 8/day · 6:00 AM',
    icon: Icons.favorite_border_rounded,
    interval: Duration(hours: 2),
    snooze: Duration(minutes: 5),
    dayStart: TimeOfDay(hour: 6, minute: 0),
    maxTimesPerDayEnabled: true,
    maxTimesPerDay: 8,
    enabledWeekdays: RA_WeekdaySchedule.allDaysMask,
    compensation: DriftCompensationTypeCodeEnum.ActualDismissal,
  );

  static const List<RA_RoutineTemplate> all = [
    medication,
    focusHydration,
    nightShiftFifo,
    caregiverCheck,
  ];
}
