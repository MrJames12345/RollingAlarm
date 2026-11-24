import 'package:flutter/material.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';
import 'package:rolling_alarm/services/swing_roster.dart';
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
  final int cycleOnDays;
  final int cycleOffDays;

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
    this.cycleOnDays = 0,
    this.cycleOffDays = 0,
  });

  /// True when this template includes an automatic N-on / M-off swing cycle.
  bool get hasSwingCycle => cycleOnDays > 0 && cycleOffDays > 0;

  /// True when this template defaults to a Pro-gated drift mode.
  bool get usesProDriftMode =>
      compensation == DriftCompensationTypeCodeEnum.InitialRing;

  /// True when this template's swing roster cycle requires Pro (e.g. `2/1`, `2/2`).
  bool get usesProSwingCycle =>
      hasSwingCycle &&
      !RA_SwingRosterSchedule.isFreeCyclePair(
        cycleOnDays: cycleOnDays,
        cycleOffDays: cycleOffDays,
      );

  /// True when any feature in this template requires Rolling Alarm Pro.
  bool get isProTemplate => usesProDriftMode || usesProSwingCycle;

  /// Effective drift compensation given the user's current entitlement.
  DriftCompensationTypeCodeEnum effectiveCompensation({required bool isPro}) {
    if (usesProDriftMode && !isPro) {
      return DriftCompensationTypeCodeEnum.ActualDismissal;
    }
    return compensation;
  }

  /// Effective swing cycle (`onDays`, `offDays`) given the user's entitlement.
  ///
  /// Pro-only cycles (e.g. `14/7`) gracefully downgrade to the free `8/6`
  /// swing cycle so free users can still preview and test the routine immediately.
  ({int onDays, int offDays}) effectiveSwingCycle({required bool isPro}) {
    if (!hasSwingCycle) return (onDays: 0, offDays: 0);
    if (usesProSwingCycle && !isPro) {
      return (onDays: 8, offDays: 6);
    }
    return (onDays: cycleOnDays, offDays: cycleOffDays);
  }
}

/// Curated high-intent Day-0 routine templates for Rolling Alarm.
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

  static const RA_RoutineTemplate fifo86DaySwing = RA_RoutineTemplate(
    id: 'fifo_8_6_day',
    title: 'WA FIFO 8/6 Day Swing',
    routineName: 'FIFO 8/6 Day Swing',
    subtitle: 'Every 12h · 8d On / 6d Off · 5:00 AM',
    icon: Icons.engineering_outlined,
    interval: Duration(hours: 12),
    snooze: Duration(minutes: 10),
    dayStart: TimeOfDay(hour: 5, minute: 0),
    maxTimesPerDayEnabled: true,
    maxTimesPerDay: 1,
    enabledWeekdays: RA_WeekdaySchedule.allDaysMask,
    compensation: DriftCompensationTypeCodeEnum.ActualDismissal,
    cycleOnDays: 8,
    cycleOffDays: 6,
  );

  static const RA_RoutineTemplate nursingFourOnFourOff = RA_RoutineTemplate(
    id: 'nursing_4_4',
    title: 'Nursing 4-On / 4-Off Shift',
    routineName: 'Nursing 4/4 Shift',
    subtitle: 'Every 12h · 4d On / 4d Off · 6:00 AM',
    icon: Icons.local_hospital_outlined,
    interval: Duration(hours: 12),
    snooze: Duration(minutes: 10),
    dayStart: TimeOfDay(hour: 6, minute: 0),
    maxTimesPerDayEnabled: true,
    maxTimesPerDay: 1,
    enabledWeekdays: RA_WeekdaySchedule.allDaysMask,
    compensation: DriftCompensationTypeCodeEnum.ActualDismissal,
    cycleOnDays: 4,
    cycleOffDays: 4,
  );

  static const RA_RoutineTemplate fifo21NightSwing = RA_RoutineTemplate(
    id: 'fifo_2_1_night',
    title: 'WA FIFO 2/1 Night Swing',
    routineName: 'FIFO 2/1 Night Swing',
    subtitle: 'Every 12h · 14d On / 7d Off · 5:30 PM',
    icon: Icons.nightlight_outlined,
    interval: Duration(hours: 12),
    snooze: Duration(minutes: 10),
    dayStart: TimeOfDay(hour: 17, minute: 30),
    maxTimesPerDayEnabled: true,
    maxTimesPerDay: 1,
    enabledWeekdays: RA_WeekdaySchedule.allDaysMask,
    compensation: DriftCompensationTypeCodeEnum.ActualDismissal,
    cycleOnDays: 14,
    cycleOffDays: 7,
  );

  static const RA_RoutineTemplate focusHydration = RA_RoutineTemplate(
    id: 'focus_hydration',
    title: 'ADHD Focus / Hydration Grid',
    routineName: 'Focus & Hydration',
    subtitle: 'Every 90m · 8/day · Mon–Fri · Initial Ring',
    icon: Icons.water_drop_outlined,
    interval: Duration(hours: 1, minutes: 30),
    snooze: Duration(minutes: 5),
    dayStart: TimeOfDay(hour: 8, minute: 0),
    maxTimesPerDayEnabled: true,
    maxTimesPerDay: 8,
    enabledWeekdays: weekdaysMask,
    compensation: DriftCompensationTypeCodeEnum.InitialRing,
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
    fifo86DaySwing,
    nursingFourOnFourOff,
    fifo21NightSwing,
    focusHydration,
    caregiverCheck,
  ];
}
