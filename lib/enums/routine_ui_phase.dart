/// UI phase derived from [RoutineStateModel] for card / home transitions.
enum RA_RoutineUiPhase {
  notScheduled,
  idle,
  countingDown,
  ringing,
  loading,
  error,
}

/// Snapshot of the fields that drive routine card chrome and status UI.
/// Equality is intentionally limited to phase + next trigger so snooze
/// counters and other state noise do not rebuild the card.
class RA_RoutineUiSnapshot {
  final RA_RoutineUiPhase phase;
  final DateTime? nextTriggerTime;

  const RA_RoutineUiSnapshot({required this.phase, this.nextTriggerTime});

  const RA_RoutineUiSnapshot.notScheduled()
    : phase = RA_RoutineUiPhase.notScheduled,
      nextTriggerTime = null;

  const RA_RoutineUiSnapshot.idle()
    : phase = RA_RoutineUiPhase.idle,
      nextTriggerTime = null;

  const RA_RoutineUiSnapshot.ringing()
    : phase = RA_RoutineUiPhase.ringing,
      nextTriggerTime = null;

  const RA_RoutineUiSnapshot.countingDown(DateTime next)
    : phase = RA_RoutineUiPhase.countingDown,
      nextTriggerTime = next;

  const RA_RoutineUiSnapshot.loading()
    : phase = RA_RoutineUiPhase.loading,
      nextTriggerTime = null;

  const RA_RoutineUiSnapshot.error()
    : phase = RA_RoutineUiPhase.error,
      nextTriggerTime = null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RA_RoutineUiSnapshot &&
          phase == other.phase &&
          nextTriggerTime?.millisecondsSinceEpoch ==
              other.nextTriggerTime?.millisecondsSinceEpoch;

  @override
  int get hashCode =>
      Object.hash(phase, nextTriggerTime?.millisecondsSinceEpoch);
}
