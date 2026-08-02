# Rolling Alarm: Logo Design Brief

## What it is

**Rolling Alarm** is an Android app for **interval based recurring alarms**. You set a routine with an interval (for example every 4 hours). When the alarm rings and you dismiss, skip, or snooze, the next fire is calculated from that action. The schedule **keeps rolling forward**. It does not lock to a fixed clock time like “every day at 7:00.”

**One line:** A calm, clinical interval alarm that rolls the next ring from what you just did, not from a wall clock.

**Who it is for:** People who need repeating relative reminders (medication cadence, care schedules, focus loops, anything “again in X”), not classic wake up alarms.

---

## The product idea in one metaphor

Think of a **dial that never sits still**. Each routine is a cycle. Time moves around the track. The next alarm is a marker on that track. When you act (dismiss, snooze, skip), the marker rolls ahead by the interval (or snooze delay). The app is the instrument that keeps that cycle honest.

That is the heart of the brand: **rolling cycle + precise next fire**, not a bell on a nightstand.

---

## How it works (designer relevant)

1. **Routine:** Named config with interval, snooze length, sound, optional daily cap, weekdays, drift mode.
2. **Countdown:** Home shows live `HH:MM:SS` until the next fire. Digits stay sage while calm, shift toward coral as time runs out, solid coral under 60 seconds.
3. **Ring:** Full screen takeover. Copy like `ALARM RINGING`. Soft coral pulse. Snooze and Dismiss are the primary actions.
4. **Snooze / Auto snooze:** Delays the next ring. If ignored, the system auto snoozes. Unlimited.
5. **Dismiss:** Ends the ring; next fire is recalculated from the interval and drift mode.
6. **Skip / Dismiss Early:** While idle, jump the pending fire to `now + interval`.
7. **Pause / Mute:** Freeze the countdown, or keep schedule but fire silently.
8. **Widget:** Quiet dark dashboard: next clock time, interval, dismissals today (not a live countdown).

**Drift compensation** (product specific, optional to show in a logo):

- **Actual Dismissal:** next = dismiss time + interval (snooze adds drift)
- **Classic Interval:** next = first ring of the cycle + interval (snooze is absorbed)

---

## What makes it different from a normal alarm

| Normal alarm | Rolling Alarm |
| --- | --- |
| Fixed time (7:00 AM) | Relative interval after last action |
| One shot or daily clock repeat | Continuous rolling cycle |
| Snooze is a side note | Snooze / auto snooze / dismiss / skip are the cycle engine |
| Often playful or loud lifestyle | Clinical instrument, OLED dark, muted accents |

**Do not design for:** classic alarm clock, 7 AM sunrise, one shot kitchen timer, random “rolling window,” fitness streaks, spa wellness, or emergency medical panic.

---

## Brand personality

**Calm clinical instrument with a controlled urgent phase.**

- Most of the time: quiet, precise, dark, soft sage glow, tabular digits.
- At ring time: dusty coral urgency, still muted, never screaming neon or cartoon.
- Language feel: `Drift Compensation`, `Classic Interval`, `Max times in a day`, `Morning Medication`. Functional, not cute.

**Tone words that fit:** rolling, interval, cycle, orbit, dial, countdown, surgical, clinical, OLED night, soft pulse.

**Tone words that do not:** playful, party, gamified, dreamy wellness, panic red, purple tech cliché.

---

## Visual system (use these)

### Colors (stable accents)

| Role | Hex | Use in logo |
| --- | --- | --- |
| Sage teal (primary brand) | `#6B9A92` | Main mark, calm track, “alive” state |
| Soft coral (alert) | `#C17F74` | Next fire / ring / tip / accent only |
| Sleep indigo (quiet) | `#4A4766` | Secondary track, depth, night chrome |
| Near black scaffold | `#0A0A0A` | Icon background |
| Charcoal surface | `#161616` | Soft lift / vignette |
| Warm white text | `#D4D2CF` | Optional wordmark or hub highlight |
| On accent ink | `#0A0A0A` | Text/icons on sage or coral fills |

Light mode exists (`#F5F4F1` paper, `#2C2B2A` text) but the **icon and logo default should feel dark first**. Accents stay the same in both themes.

### Shape and type in the app (not required for the mark)

- Radius language: **16** on cards and buttons, soft but not bubbly.
- Soft dual glows: sage glow when calm/active, coral glow when urgent.
- UI type is Inter with tabular figures. The **logo mark should not depend on Inter**; wordmark (if any) can be quieter and more distinctive.

---

## Brandable moments to encode

1. **Rolling open dial / orbit:** incomplete circle = interval still in motion.
2. **Leading marker:** coral tip, bead, or needle = “next alarm.”
3. **Nested cycle:** inner quieter arc = depth / recurring routine.
4. **Countdown tension:** sage calm → coral urgency (optional in animated versions).
5. **Squircle app icon:** dark field, soft neon tube glow, thick rounded strokes.

Existing concept on disk: `assets/branding/logo_concept_orbital.svg` (indigo track, sage rolling arc, coral leading capsule, quiet hub). Treat that as one valid direction, not the only one.

---

## Name and copy anchors

- Product name: **Rolling Alarm**
- Package / id: `rolling_alarm` / `com.example.rolling_alarm`
- Useful strings: `ALARM RINGING`, `Next: …`, `Interval`, `Dismissed`, `Slide to snooze`, `Classic Interval`, `Actual Dismissal`

Default example routine vibe: **Morning Medication**, automated care or habit cadence, not “Wake Up.”

---

## Logo design constraints (practical)

1. Must read at **app icon size** (tiny): prefer 1–3 bold shapes, thick rounded strokes.
2. **Sage must dominate**; coral is the spark, not half the mark.
3. Prefer **abstract cycle / orbit / rolling dial** over a literal bell, unless the bell is heavily rethought as a cycle mark.
4. Avoid fixed clock hands that shout “wake up at 7.”
5. Soft glow is on brand for dark icons; keep it subtle so it still works flat (Play Store, monochrome, notification).
6. Deliver: full color dark squircle, flat mark on transparent, and a single color (sage or warm white) for badges.

---

## One sentence for the designer

**Design a dark, clinical mark for a rolling interval alarm: a quiet orbit or dial in sage teal, with a small coral point that means “the next fire,” never a classic wake up clock.**
