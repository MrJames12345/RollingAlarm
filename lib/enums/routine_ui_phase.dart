/// UI phase derived from [RoutineStateModel] for card / home transitions.
enum RA_RoutineUiPhase {
  notScheduled,
  idle,
  countingDown,
  paused,
  ringing,
  loading,
  error,
}

/// Snapshot of the fields that drive routine card chrome and status UI.
/// Equality is intentionally limited to phase + next trigger + pause so snooze
/// counters and other state noise do not rebuild the card.
class RA_RoutineUiSnapshot {
  final RA_RoutineUiPhase phase;
  final DateTime? nextTriggerTime;
  final DateTime? pausedAt;

  const RA_RoutineUiSnapshot({
    required this.phase,
    this.nextTriggerTime,
    this.pausedAt,
  });

  const RA_RoutineUiSnapshot.notScheduled()
    : phase = RA_RoutineUiPhase.notScheduled,
      nextTriggerTime = null,
      pausedAt = null;

  const RA_RoutineUiSnapshot.idle()
    : phase = RA_RoutineUiPhase.idle,
      nextTriggerTime = null,
      pausedAt = null;

  const RA_RoutineUiSnapshot.ringing()
    : phase = RA_RoutineUiPhase.ringing,
      nextTriggerTime = null,
      pausedAt = null;

  const RA_RoutineUiSnapshot.countingDown(DateTime next)
    : phase = RA_RoutineUiPhase.countingDown,
      nextTriggerTime = next,
      pausedAt = null;

  const RA_RoutineUiSnapshot.paused({
    required this.pausedAt,
    this.nextTriggerTime,
  }) : phase = RA_RoutineUiPhase.paused;

  const RA_RoutineUiSnapshot.loading()
    : phase = RA_RoutineUiPhase.loading,
      nextTriggerTime = null,
      pausedAt = null;

  const RA_RoutineUiSnapshot.error()
    : phase = RA_RoutineUiPhase.error,
      nextTriggerTime = null,
      pausedAt = null;

  /// Remaining duration frozen at the pause instant, or null when idle paused.
  Duration? get pausedRemaining {
    final next = nextTriggerTime;
    final paused = pausedAt;
    if (next == null || paused == null) return null;
    final rem = next.difference(paused);
    return rem.isNegative ? Duration.zero : rem;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RA_RoutineUiSnapshot &&
          phase == other.phase &&
          nextTriggerTime?.millisecondsSinceEpoch ==
              other.nextTriggerTime?.millisecondsSinceEpoch &&
          pausedAt?.millisecondsSinceEpoch ==
              other.pausedAt?.millisecondsSinceEpoch;

  @override
  int get hashCode => Object.hash(
    phase,
    nextTriggerTime?.millisecondsSinceEpoch,
    pausedAt?.millisecondsSinceEpoch,
  );
}
