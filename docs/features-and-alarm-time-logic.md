# Rolling Alarm: Features and Alarm Time Logic

Rolling Alarm is an **interval based recurring alarm app**. Every routine rolls forward from Dismiss, Skip, or Snooze. There are no fixed “alarm at 7:00” modes, no one shot alarms, and no random windows. Day Start Time is only used as a daily period boundary / parking point when the cap or weekday rules kick in.

---

## Mental model

Three pure layers compute times, then `RA_AlarmService` persists and arms the OS:

| Layer | File | Job |
| --- | --- | --- |
| Interval / action math | `lib/services/alarm_calculator.dart` | Dismiss, Snooze, Skip, AutoSnooze |
| Daily cap + day start | `lib/services/daily_ring_limit.dart` | Cap, period boundaries, create/edit retarget |
| Weekdays | `lib/services/weekday_schedule.dart` | Enabled days + deferral |
| Orchestration | `lib/services/alarm.dart` | Fire, count, pause/resume/mute, OS schedule |

Source of truth for “when does it fire next” is `RoutineStates.NextTriggerTime`. OS timers are rearmed from that value.

---

## 1. Feature inventory

### Routines (core)

- Create, edit, soft delete
- Fields: name, interval, snooze duration, sound / volume / fade in / vibrate, drift compensation, optional daily ring cap, day start time, enabled weekdays
- Home cards with live countdown
- Summary page with history

### Rolling interval alarms

- After a cycle ends (Dismiss or Skip), next fire is based on the interval
- Not locked to a wall clock time, except when parked on Day Start Time by the daily cap or weekday deferral

### Drift compensation (2 modes) 

- **Actual Dismissal:** next = dismiss time + interval (snooze time adds drift)
- **Initial Ring (Classic Interval):** next = first ring of this cycle + interval (snooze time is absorbed)

### Snooze / Auto snooze

- Manual snooze from ring UI, notifications, or side buttons
- Auto snooze watchdog: if ignored for `SnoozeSeconds`, system auto snoozes
- Unlimited snoozes
- Snooze does **not** increment the daily ring counter again

### Dismiss

- Ends the ring cycle, recalculates next interval fire, resets snooze count, logs dismiss

### Dismiss Early (Skip)

- Idle skip of the pending next fire; retargets to `now + interval` (then daily / weekday filters)
- Prompt: whether to count toward today’s daily total
- Available whenever the routine is not paused, including when next fire is already a day start ("Starts at") boundary

### Daily ring limit

- Optional max **fresh** rings per day period
- Day period starts at configurable Day Start Time (not necessarily midnight)
- When cap is hit, or next interval would cross the next day start, next fire snaps to next day start
- Manual “Reset today’s counter” zeros the count; if the prior count had hit the daily cap and next was parked on day start, retargets to `now + interval` and re-arms

### Enabled weekdays

- Monday first bitmask (`EnabledWeekdays`)
- If a proposed fire lands on a disabled day, defer to the next enabled day at Day Start Time
- UI cannot turn off the last remaining weekday; zero mask is treated as all days

### Pause / Resume

- Pause: cancel OS timers, `IsActive=false`, freeze remaining countdown (day start targets keep absolute time)
- Resume: restore remaining, or for a missed day start use the sooner of `now + interval` vs next day start

### Mute / Unmute

- Schedule keeps running; fires silently auto dismiss and still count
- Muting while paused clears pause first (resume then mute)
- Unmute does not change next fire time

### Ring UI + reliability

- Full screen ring page (sliders or buttons layout)
- Volume side buttons: None / Snooze / Dismiss
- Preview from editor (no schedule side effects)
- Native `setAlarmClock` / FSI / AlarmManager / battery exemption for OEM reliability
- Home widget: name, next alarm clock time, interval label, dismissals today

### Logging

- Dismiss / Snooze / Skip / AutoSnooze logged
- Optional time since last dismissal; muted fires flagged `WasMuted`
- Global logs page + per routine history

### Settings

- Theme (dark / light)
- Alarm snooze/dismiss layout
- Side button actions
- Swipe actions on routine cards
- Import / export (RA1 base64)

### What does not exist

- No random / rolling time window
- No one time alarm type
- No “alarm at fixed HH:MM every day” mode
- No explicit timezone / DST library (device local `DateTime` duration math only)

---

## 2. Data that affects time

### Routine config (`Routines`)

| Field | Effect |
| --- | --- |
| `IntervalSeconds` | Base cycle length for Dismiss / Skip / create without cap |
| `SnoozeSeconds` | Snooze + AutoSnooze delay; also watchdog length |
| `DriftCompensationTypeCode` | ActualDismissal vs InitialRing on Dismiss |
| `MaxTimesPerDayEnabled` / `MaxTimesPerDay` | Cap on fresh rings; enables day start parking |
| `DayStartSeconds` | Period boundary + weekday deferral clock |
| `EnabledWeekdays` | Which calendar days may fire |
| `IsActive` | Pause clears this; inactive routines ignore fires |

### Live state (`RoutineStates`)

| Field | Effect |
| --- | --- |
| `NextTriggerTime` | Scheduled fire instant (OS rearm source of truth) |
| `InitialRingTime` | Anchor for InitialRing compensation |
| `CurrentSnoozeCount` | `> 0` means snooze resume (preserve initial ring; don’t re count) |
| `TimesRingToday` / `TimesRingDay` | Cap accounting for current day period |
| `IsRinging` | Live ring; CAS guard for transitions |
| `PausedAt` | Freeze remaining = `NextTriggerTime` minus `PausedAt` |
| `MutedAt` | Silent dismiss path on fire |
| `LastDismissedAt` | Logging only (not used in next time math) |

---

## 3. Base formulas (`RA_AlarmCalculator`)

Source: `lib/services/alarm_calculator.dart`

```dart
static DateTime calculateNextTrigger({...}) {
  return switch (Action) {
    Dismiss => _calculateDismiss(...),
    Snooze || AutoSnooze => Now.add(snoozeDuration),
    Skip => Now.add(interval),
  };
}

static DateTime _calculateDismiss(...) {
  switch (Compensation) {
    ActualDismissal => return Now.add(Interval);
    InitialRing => {
      var next = InitialRingTime.add(Interval);
      while (!next.isAfter(Now)) next = next.add(Interval);
      return next;
    }
  }
}
```

| Action | Formula |
| --- | --- |
| **Dismiss + Actual Dismissal** | `Now + Interval` |
| **Dismiss + Initial Ring** | First `InitialRingTime + n·Interval` strictly after `Now` |
| **Snooze** | `Now + Snooze` |
| **AutoSnooze** | `Now + Snooze` (same) |
| **Skip** | `Now + Interval` (ignores compensation) |

Example: first ring 06:00, dismiss 06:23:17, interval 4h30m

- Actual Dismissal → **10:53:17**
- Initial Ring → **10:30:00**

---

## 4. Post filters (after the calculator)

Applied only for **Dismiss** and **Skip** (and muted dismiss / pause while ringing). **Snooze and AutoSnooze skip both filters.**

```
next =
  deferToEnabledDay(
    deferIfDailyLimitReached(calculated, …),
    EnabledWeekdays,
    dayStartSeconds
  )
```

### Daily cap (`deferIfDailyLimitReached`)

If `maxTimesPerDay <= 0` (feature off): return proposed unchanged.

Else:

1. `dayStart = nextPeriodStartAfter(now)`
2. If `proposed >= dayStart`: return `dayStart` (even under cap; long intervals cannot skip into a new period)
3. If count ≥ max: return `dayStart`
4. Else return `proposed`

### Day period definition

A “day” is `[dayStart, dayStart + 24h)`, not calendar midnight unless `DayStartSeconds == 0`.

If `now` is before today’s day start clock, the current period started yesterday at that clock.

### Weekday deferral (`deferToEnabledDay`)

If all days enabled (or mask is 0): return proposed.

If today’s weekday is enabled: return proposed **unchanged** (keeps original time of day).

Else: walk forward up to 7 days; land on the first enabled day at local `(hour, minute, second)` from `DayStartSeconds` (not at the original proposed time of day).

---

## 5. Every case where next fire time is set

### A) Create routine

`routine_edit.dart` → `RA_DailyRingLimit.initialTriggerTime`

- Cap **on** → next Day Start Time after now
- Cap **off** → `now + interval`
- Then weekday deferral
- Persist + `scheduleNext`

### B) Import routines

Same `initialTriggerTime` as create, then OS arm after import.

### C) Edit routine (selective retarget)

`retargetNextAfterEdit`. Interval / snooze / compensation edits alone **do not** move the active timer (“apply next cycle”). Retarget only when:

| Situation | New next |
| --- | --- |
| Cap newly at/over today’s count | Next day start |
| Cap newly under count (was blocked) | `now + interval`, then daily defer snap |
| Day start clock changed **and** previous next was a day start boundary | New next day start |
| Otherwise | Keep `previousNext` |

Always ends with weekday deferral. Then `scheduleNext` if changed (or rearm).

### D) OS arming (`scheduleNext`)

Does not recalculate. Clamps past times:

`fireAt = triggerTime.isAfter(now) ? triggerTime : now + 1s`

Arms `AndroidAlarmManager.oneShotAt` + native UI `setAlarmClock`.

### E) Startup reconcile

Re arms from stored `NextTriggerTime` (or restarts watchdog if already ringing). No new arithmetic unless the past clamp in `scheduleNext`.

### F) Alarm fire (fresh cycle gates)

In `_alarmCallback`, if **not** snooze resume (`CurrentSnoozeCount == 0`):

1. Deleted / inactive → cancel, return
2. Disabled weekday → set next = `deferToEnabledDay(now, …)`, reschedule, **no ring**
3. Cap exhausted → next = next day start (+ weekday defer), reschedule, **no ring**
4. Muted → silent dismiss path (below)
5. Else: `TimesRingToday += 1`, `InitialRingTime = now`, `IsRinging = true`, arm watchdog, show ring UI / audio

Snooze resume only sets `IsRinging = true` (preserves initial ring + count). **Bypasses** weekday and daily gates.

### G) Muted fire

Count if fresh; compute Dismiss next via calculator + daily + weekday; schedule; log Dismiss with `WasMuted=true`. No UX.

### H) User / system transition (`handleTransition`)

Callers: ring page, notifications, watchdog, skip from routine card.

1. `calculated = calculateNextTrigger(...)`
2. If Dismiss or Skip: daily defer then weekday defer; else use calculated raw
3. Persist `NextTriggerTime`, clear ringing, snooze count (0 on dismiss/skip, +1 on snooze)
4. Optional idle Skip daily increment if `countSkipTowardsDaily`
5. `scheduleNext(next)`

CAS: ringing actions require `IsRinging == true`; idle Skip locks on matching prior `NextTriggerTime`. Lost races return without rescheduling.

### I) Auto snooze watchdog

At ring start, watchdog armed for `now + SnoozeSeconds`. Callback → `handleTransition(AutoSnooze)`.

### J) Pause

If currently ringing: compute Dismiss style next (with daily + weekday), store it, **do not schedule**.

Then:

- If next is a day start boundary → keep absolute `NextTriggerTime`
- Else freeze: `next = floor(now) + floor(remainingSeconds)`

Set `IsActive=false`, cancel OS alarms. Clears mute.

### K) Resume

- Day start target still in future → keep it
- Day start missed → `min(now + interval, next day start)`
- Interval target → `now + frozenRemaining`
- Then weekday deferral; `scheduleNext`

### L) Mute while ringing

May `resumeRoutine` first; if ringing, `handleTransition(Dismiss)` then set `MutedAt`.

### M) Soft delete

`NextTriggerTime = null`; cancel OS timers.

### N) Reset today’s counter

Sets `TimesRingToday = 0` for the current period. When the prior count had exhausted the daily cap and `NextTriggerTime` is parked on a day-start boundary, retargets to `now + interval` (then daily / weekday filters) and re-arms the OS timer so alarms can resume today. Otherwise leaves `NextTriggerTime` unchanged.

---

## 6. Priority / order of operations

### On Dismiss or Skip

1. Action base time (calculator)
2. Daily limit snap
3. Weekday deferral
4. Persist + OS arm (past → `now + 1s`)

Snooze / AutoSnooze stop after step 1.

### On fire (fresh cycle)

1. Deleted / inactive → cancel
2. Disabled weekday → defer, no ring
3. Daily cap full → park at next day start (+ weekday), no ring
4. Muted → silent dismiss
5. Else ring + count + watchdog

### Create / import

1. Cap? day start : `now + interval`
2. Weekday deferral
3. Persist + schedule

### Pause / resume specials

- Day start targets are **absolute wall clocks** (matched by time of day to `DayStartSeconds`)
- Interval targets are **relative remaining** frozen across pause
- Resume of a missed day start prefers the **sooner** of interval vs next day start

---

## 7. Edge cases

### Custom day periods

Period is not midnight unless day start is 00:00. Before today’s day start, “today’s period” is yesterday’s day start.

### Long intervals under a cap

Even if under the count, any proposed next that reaches/passes the next day start snaps to that day start, so a cycle cannot skip the daily reset.

### DST / timezone

No timezone package. Adds wall clock `Duration` on device local `DateTime`. Spring forward / fall back behave as naive duration addition.

### Disabled days

Deferral parks at **day start**, not the original proposed time of day. Fire time re checks and re defers if somehow scheduled on a disabled day.

### What counts toward the daily cap

- Fresh ring at trigger (before UX)
- Optional idle Skip when user says yes
- Muted fresh fires
- Snooze re rings do **not** count again

### Missed / past triggers

Never dropped; `scheduleNext` fires in ~1 second. Startup reconcile re arms all active routines.

### InitialRing with a very late dismiss

If `InitialRingTime + Interval` is already in the past (long snooze chain), the calculator skips forward by whole intervals until the candidate is strictly after `Now`, so dismiss does not clamp and re-ring immediately.

### Pause while ringing

Ends ring as a dismiss style next time, stores it, does not schedule until resume.

### Dismiss Early while next is day start

Still offered (unless paused). Skip calculates `now + interval` and then applies the usual daily / weekday filters, so under the cap it can leave a parked "Starts at" and begin a fresh cycle immediately.

---

## 8. Quick map of “when is next set?”

```
Create / Import ──► initialTriggerTime (cap? dayStart : now+interval) + weekdays
Edit ─────────────► retargetNextAfterEdit (only cap / day-start boundary cases)
Dismiss / Skip ───► calculator → daily defer → weekday defer → schedule
Snooze / Auto ────► now + snooze (no daily/weekday filters)
Fire (blocked) ───► weekday defer or next day-start (+ weekday)
Muted fire ───────► same as Dismiss path (silent)
Pause ────────────► dismiss-style next if ringing; freeze remaining (or keep day-start)
Resume ───────────► restore remaining / keep day-start / earliest after missed
Reset counter ────► count = 0; unpark day-start when prior cap hit, else keep next
Delete ───────────► NextTriggerTime = null
Startup ──────────► re-arm stored NextTriggerTime (clamp if past)
```

---

## Key source files

| Concern | Path |
| --- | --- |
| Interval math | `lib/services/alarm_calculator.dart` |
| Daily cap / day start / create / edit retarget | `lib/services/daily_ring_limit.dart` |
| Weekdays | `lib/services/weekday_schedule.dart` |
| Fire / transition / pause / mute / schedule | `lib/services/alarm.dart` |
| Create/edit save | `lib/pages/routine_edit.dart` |
| Import seeding | `lib/services/export.dart` |
| Routine schema | `lib/database/tables/routines.dart` |
| State schema | `lib/database/tables/routine_states.dart` |
| Calculator tests | `test/services/alarm_calculator_test.dart` |
| Cap tests | `test/services/daily_ring_limit_test.dart` |
| Weekday tests | `test/services/weekday_schedule_test.dart` |
