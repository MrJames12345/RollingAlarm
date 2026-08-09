# Rolling Alarm: Google Stitch Master UI Blueprint

> Paste this entire document into Google Stitch as one prompt.  
> Complete functional + visual spec. No placeholders. No follow-up questions required.  
> Redesign visuals from this system only. Preserve every screen, flow, data field, and interaction.

---

## 1. App Context & User Scope

### App Description
**Rolling Alarm** is an Android interval-based recurring alarm app. Each “routine” is a continuous cycle: after the user dismisses, snoozes, skips, or ignores a ring, the next fire time is calculated from intervals (not fixed wall-clock schedules). Optional daily caps, day-start boundaries, weekday filters, pause/mute, and drift compensation control when alarms fire again. Soft-deleted routines remain recoverable. Import/export uses shareable RA1 strings. A home-screen widget shows live summary stats per routine.

**What the product is not:** one-shot timers, fixed “alarm every day at 7:00” modes, random/window rolling, multi-user accounts, or cloud sync.

### Target User
A single user who needs **reliable, repeating interval alarms** for medication, habits, caregiving checks, or any task that must recur every N hours/minutes rather than at a clock time. They care about:
- Seeing the next fire clearly (live countdown + clock time)
- Controlling today’s ring budget (daily max, adjust max, reset counter)
- Fast actions from home (swipe, card buttons, long-press menu)
- Quiet operation (mute) vs frozen schedule (pause)
- Audible ring UX that is hard to dismiss by accident (slide or big buttons)
- History for accountability (logs + PDF share)

### Core Navigation Pattern
**Stack navigation from a single home root (no bottom tabs, no side drawer).**

| Layer | Pattern |
| --- | --- |
| **Root** | Home (routine list) |
| **Primary destinations** | Settings, Alarm Logs, New/Edit Routine, Routine Summary (from home app bar / FAB / card tap) |
| **Secondary destinations** | Alarm Sound Picker, Alarm Ring (from edit / live fire / ringing card) |
| **Chrome** | Sticky top AppBar per screen; title + optional leading close/back + trailing actions; optional FAB on Home and Sound Picker |
| **Overlays** | Full-screen Alarm Ring page above any route; modal dialogs for confirmations and pickers; system permissions on cold start (not branded screens) |
| **External surfaces** | Android home-screen widget (name, next alarm clock time, interval, dismissals today); no in-app notification action UI as primary ring (full-screen ring is the primary UX) |

### Navigation Map (user flows)

```
Home
├── [Settings icon] → Settings
│   ├── Theme / Alarm Layout / Side Buttons / Swipe / Card Buttons (inline + picker dialogs)
│   ├── Export Routines → Export dialog
│   └── Import Routines → Import dialog
├── [Logs icon] → Alarm Logs
│   ├── [Share PDF] (only if logs exist)
│   └── Recover on soft-deleted Delete log entries → Recover dialog
├── [+ FAB] or empty-state CTA → New Routine (Edit page, create mode)
│   ├── Alarm sound field → Alarm Sound Picker → (optional) Preview opens Alarm Ring (preview)
│   └── Preview button → Alarm Ring (preview: no schedule side effects)
├── Routine Card
│   ├── Tap (not ringing) → Routine Summary
│   │   ├── Summary tab (tappable fields → Edit focused field)
│   │   ├── History tab (per-routine logs, Recover if applicable)
│   │   └── [Edit icon] → Edit Routine
│   ├── Tap (ringing) → Alarm Ring (live)
│   ├── Swipe L/R → configured actions (Mute / Pause / Dismiss Early / Adjust Max / Delete)
│   ├── Bottom L/R icon buttons → same action set (configurable)
│   └── Long-press → Actions menu dialog
└── OS alarm fire (any screen) → Alarm Ring pushed full-screen (cannot back-dismiss unless preview)
```

---

## 2. Screen-by-Screen Functional Breakdown

### 2.1 Home (Routine Dashboard)
**Screen Name & Route:** Home `/` (MaterialApp `home`; root of stack)

**Goal of the Screen:** See all active (non-deleted) routines at a glance, scan next fire / status, create new routines, jump to settings/logs, run quick actions without opening detail.

**Layout Hierarchy**
1. **Primary:** Scrollable list of routine cards (one per routine)
2. **Secondary:** Top AppBar with brand title “Rolling Alarm”, Settings, Alarm Logs
3. **Tertiary:** FAB “add” to create routine; empty/error states when list unavailable

**Required Data (per routine card)**
- Routine **name**
- **Interval** display (formatted duration, e.g. hours/minutes)
- **Status phase** (exactly one logical state at a time):
  - Ringing: label “RINGING”
  - Counting down: live `HH:MM:SS` countdown toward `NextTriggerTime`
  - Muted: same countdown + muted “next fire” caption + mute indicator icon
  - Paused: frozen remaining duration (if available) + “Paused” with pause icon
  - Idle / Not scheduled / Loading spinner / Unavailable (error)
- **Next fire caption** when counting down or muted: clock-time style caption (e.g. time today/tomorrow, with muted variant wording when muted)
- **Today’s ring count** when today’s logical day-period weekday is enabled:
  - With daily max on: `count/max times today` (max = base MaxTimesPerDay + extra for today)
  - With daily max off: `N time(s) today`
  - Hidden when logical day is a disabled weekday
- **Enabled weekdays strip** (M T W T F S S) only when not every day enabled: each day letter on/off
- Visual weight for phase (functional, not specific colors): ringing emphatic; active countdown active; muted/paused subdued; muted badge

**Required Components/Interactions**
- [ ] AppBar: title “Rolling Alarm”
- [ ] AppBar action: open Settings
- [ ] AppBar action: open Alarm Logs
- [ ] FAB: open New Routine editor
- [ ] Empty state: icon, “No Routines Yet”, helper copy; tappable icon creates new routine
- [ ] Loading state for list
- [ ] Error state: “Could Not Load Routines” + Retry
- [ ] Routine card **tap**: if ringing → open Alarm Ring; else → Routine Summary
- [ ] Routine card **long-press** → Routine Card Actions menu dialog
- [ ] **Swipe left / right**: configurable per Settings (defaults: Left=Delete, Right=Pause/Resume)
- [ ] **Bottom-left / bottom-right icon buttons** on each card: configurable (defaults: Left=Adjust Today’s Max, Right=Dismiss Early)
- [ ] Action set available from swipe, card buttons, and long-press menu (subset): Mute/Unmute, Pause/Resume, Dismiss Early, Adjust Today’s Max, Delete (with confirm), Edit, Duplicate, Reset Today’s Counter (menu only for last three where noted)
- [ ] Dismiss Early → Count Daily Skip dialog before running skip
- [ ] Delete → Delete confirmation dialog; soft-delete only
- [ ] Adjust Today’s Max → dialog with current max prefilled (+/− and numeric entry)
- [ ] Reset Today’s Counter (from long-press menu) → confirmation dialog

**Card-driven phase model (must remain expressible in UI)**
| Phase | What user sees | Meaning |
| --- | --- | --- |
| `countingDown` | Live countdown + next-fire caption | Active scheduled fire |
| `muted` | Countdown + muted caption + mute glyph | Schedule continues; fires silent |
| `paused` | Frozen remaining + Paused | Timers canceled; freeze remaining |
| `ringing` | RINGING; tap opens ring UI | Alarm currently ringing |
| `idle` / `notScheduled` | Label text | No useful next fire |
| `loading` / `error` | Spinner / Unavailable | Transient |

---

### 2.2 Alarm Ring (Live)
**Screen Name & Route:** Alarm Ring `ra_alarm_ring` (named full-screen route, opaque, presented over stack)

**Goal of the Screen:** Force attention when a routine rings; only intentional snooze or dismiss ends the cycle (or auto-snooze watchdog after snooze duration if ignored).

**Layout Hierarchy**
1. **Primary:** Urgency visual focus (alarm icon / pulse), **routine name** large, fixed label “ALARM RINGING”
2. **Secondary:** Live clock (updates every second)
3. **Tertiary:** Snooze + Dismiss controls (layout mode from Settings)

**Required Data**
- Routine name
- Routine id (for state binding; not necessarily visible)
- Audio/vibrate/volume/fade-in config (drives media; not all need permanent labels)
- Settings: Snooze/Dismiss layout (Sliders vs Buttons)
- Side button mapping (Volume Up / Volume Down → None | Snooze | Dismiss)
- Busy/disabled state while transition runs

**Required Components/Interactions**
- [ ] Full-screen takeover; **system back blocked** for live rings
- [ ] Live current-time clock
- [ ] Snooze action (side effects: reschedule, stop audio, close)
- [ ] Dismiss action (side effects: end cycle, calculate next interval fire, stop audio, close)
- [ ] **Layout mode A (Sliders):** “Slide to snooze” and “Slide to dismiss” (complete near end of track)
- [ ] **Layout mode B (Buttons):** side-by-side Snooze and Dismiss buttons
- [ ] Hardware volume keys respect Settings side-button actions
- [ ] Auto-close if ringing state clears elsewhere (e.g. external dismiss)
- [ ] Guard against double-tap / concurrent actions (`_busy`)
- [ ] Unlimited snoozes; snooze does not re-count toward daily ring cap

---

### 2.3 Alarm Ring (Preview)
**Screen Name & Route:** Same Alarm Ring UI; `isPreview: true` from Routine Edit → Preview or after sound/volume settings

**Goal of the Screen:** Let user hear/feel the configured alarm without changing schedule.

**Differences from live ring**
- [ ] Snooze/Dismiss only stop audio and pop; **no** schedule/log side effects
- [ ] System back allowed
- [ ] Does not auto-close due to other routines’ ring state
- [ ] Uses current form values (name fallback “Alarm” if empty; fade-in forced off if silent sound)

---

### 2.4 New Routine / Edit Routine
**Screen Name & Route:** New Routine | Edit Routine (pushed fade from Home / Summary / Card menu)

**Goal of the Screen:** Create or update full routine configuration; validate required fields; optionally preview, duplicate, or delete (edit only).

**Layout Hierarchy**
1. **Primary:** Identity + core timing (Name, Interval, Snooze)
2. **Secondary:** Sound section (sound, volume, fade in, vibrate, Preview)
3. **Tertiary:** Daily limit & weekdays & day start; Drift compensation
4. **Footer actions (edit only):** Duplicate, Delete

**Required Data / Form Fields**

| Field | Type | Rules / Defaults |
| --- | --- | --- |
| Name | Text | Required; placeholder e.g. “Morning Medication” |
| Sound | Selectable summary (opens picker) | Silent / Default / device; displays label |
| Volume | Integer control 5–100 | Disabled when Silent |
| Fade in | Toggle | Disabled/forced off when Silent |
| Vibrate | Toggle | Default true |
| Interval (“Every”) | Duration H:M:S | Min 1 second; required |
| Snooze | Duration H:M:S | Min 1 second; required; also auto-snooze watchdog length |
| Max times in a day | Toggle | Default off |
| Number of times in a day | Integer 1–48 | Visible/enabled when max enabled |
| Enabled on Days | Mon–Sun bitmask (MTWTFSS) | Cannot disable last remaining day; default every day |
| Day Start Time | Time of day | Editable when max-on **or** any weekday disabled; used for period/cap parking and weekday deferral |
| Drift Compensation | Radio | “Classic Interval” (Initial Ring) vs “Actual Dismissal” (+ subtitle on Actual Dismissal) |

**Helper copy (functional, must remain available as microcopy)**
- When daily max on: explain Day Start is used when today’s count is exceeded to schedule “tomorrow”
- When weekdays incomplete: explain Day Start is used when next alarm would land on a disabled day

**Required Components/Interactions**
- [ ] AppBar title: “New Routine” or “Edit Routine”
- [ ] Close (leading) pops without explicit dirty-guard on close (except Duplicate path below)
- [ ] Save (trailing): validates, scrolls to first invalid, persists, schedules OS alarm, pop
- [ ] New mode: autofocus Name
- [ ] Deep-link style: optional scroll-to-and-highlight a specific field (from Summary tiles)
- [ ] Open Alarm Sound Picker; return selected sound
- [ ] Preview → Alarm Ring preview
- [ ] Volume changes can live-adjust system alarm volume during editing
- [ ] Edit only: **Duplicate** (if dirty → Unsaved Changes dialog → Save & Continue / Discard & Continue / Cancel); opens new Edit for copy via replace
- [ ] Edit only: **Delete** → confirm dialog → soft delete, cancel alarms, pop to Home root
- [ ] Create: seed initial next trigger (cap? next day-start : now+interval, then weekday defer)
- [ ] Edit: keep active timer unless cap/day-start boundary retarget rules apply

---

### 2.5 Alarm Sound Picker
**Screen Name & Route:** Alarm sound (from Edit sound field)

**Goal of the Screen:** Choose Silent, built-in Default, or a device tone; audition selection; save back to editor.

**Layout Hierarchy**
1. **Primary:** Fixed options: Silent, Default
2. **Secondary:** Device sounds list (searchable)
3. **Chrome:** Close, Save; FAB play/pause when a non-silent sound is selected

**Required Data (per tile)**
- Selection state (radio)
- Title (display label)
- Subtitle: Silent → “No audio”; Default → “Rolling Alarm tone”; device → optional file name when it differs from title
- Loading state while scanning device sounds
- Empty: no device sounds found
- Search no-matches empty state

**Required Components/Interactions**
- [ ] Close discards selection (no result)
- [ ] Save returns selected sound to Edit
- [ ] Tap tile selects + auto-previews (except Silent stops preview)
- [ ] Search filters device list by title or file name
- [ ] FAB: play/pause preview when non-silent selected
- [ ] Interactive scrollbar on long lists

---

### 2.6 Routine Summary
**Screen Name & Route:** Routine Summary (title = routine name; from card tap)

**Goal of the Screen:** Read-only overview of configuration, today’s count, and history; jump into Edit on any field; reset today counter.

**Layout Hierarchy**
1. **Primary:** Tab “Summary” with grouped read-only tiles
2. **Secondary:** Tab “History” (per-routine logs)
3. **Chrome:** Back, Edit (app bar), routine name as title

**Unavailable state**
- If routine missing/deleted while open: title “Routine”, status “Routine unavailable” / “This routine may have been deleted.”

**Summary tab: Required Data**

**Section: Alarm sound**
- Sound (display label), tappable, opens edit sound field
- Volume (`N%` or N/A if silent), tappable
- Fade in (On/Off or N/A if silent), tappable
- Vibrate (On/Off), tappable

**Section: Timing**
- Interval (formatted), tappable
- Snooze (formatted), tappable
- Days (`Every day` or short weekday list), tappable
- Drift compensation (`Classic Interval` | `Actual Dismissal`), tappable

**Section: Daily limit**
- Max times in a day (On/Off), tappable
- If On: Limit (number), Starts at (day-start clock time)
- Today: `N time(s)` (live count for current day period)
- Button: “Reset Today’s Counter” (secondary); confirmation zeros count (and may unpark day-start next fire)

**History tab:** same log row model as global logs, but without routine name on each tile; Recover if delete log + soft-deleted.

**Required Components/Interactions**
- [ ] Tabs: Summary | History
- [ ] Tappable summary tiles open Edit with that field scrolled into view
- [ ] Reset Counter flow
- [ ] App bar Edit opens full editor

---

### 2.7 Alarm Logs (Global)
**Screen Name & Route:** Alarm Logs (from Home)

**Goal of the Screen:** Chronological activity across all routines; recover soft-deleted routines; export PDF report.

**Layout Hierarchy**
1. **Primary:** Reverse-chronological log list
2. **Secondary:** Share PDF when non-empty
3. **Empty/error** states

**Required Data (per log entry)**
- Action type display name and semantic emphasis:
  - Dismiss, Snooze, Skip, Auto Snooze, Create, Edit, Delete, Duplicate, Pause, Resume, Mute, Unmute, Reset Counter, Ring, Recover
- Optional **Muted** flag when silent auto-dismiss produced the event
- **Routine name** (when known)
- **Timestamp** (formatted date+time)
- Optional **time since last dismissal** duration (when present and Recover not shown)
- **Recover** control when this is a Delete log for a still soft-deleted routine

**Required Components/Interactions**
- [ ] Share PDF (app bar) only when logs exist; builds PDF of full list
- [ ] Recover → Recover confirmation → reactivates routine + reschedules
- [ ] Empty: “No Log Entries Yet” + helper copy about snooze/skip/dismiss
- [ ] Error + Retry: “Could Not Load Logs”

---

### 2.8 Settings
**Screen Name & Route:** Settings (from Home)

**Goal of the Screen:** Global preferences for theme, ring controls, home-card gestures/buttons, backup.

**Layout Hierarchy:** vertical sections:

#### Theme
- Radio: **Dark** | **Light** (app chrome brightness)

#### Alarm Layout
- Radio: **Sliders** | **Buttons** (ring snooze/dismiss presentation)

#### Side Buttons
- Two tiles: **Volume Up**, **Volume Down**
- Each shows current action: None | Snooze | Dismiss
- Tap → dialog radio picker for that button

#### Swipe Actions
- Two tiles: **Left**, **Right**
- Each shows action label; options:
  - Mute
  - Pause/Resume
  - Dismiss Early
  - Adjust Today’s Max
  - Delete
- Defaults: Left=Delete, Right=Pause

#### Card Buttons
- Two tiles: **Bottom Left Button**, **Bottom Right Button**
- Same action enum as swipe
- Defaults: Left=Adjust Today’s Max, Right=Dismiss Early

#### Import/Export
- **Export Routines**: builds RA1 base64 of all routines; if none → snackbar “No routines to export…”
- Export dialog: selectable RA1 string; **Copy** (clipboard) and Close
- **Import Routines**: paste dialog `RA1:…`; Import / Cancel; failed import snackbar; successful import schedules each imported alarm

**Required Components/Interactions**
- Immediate persistence of preference changes (no global Save button)
- Dialog pickers for side/swipe/card mappings
- Import/export multimodal (dialogs + snackbars)

---

### 2.9 Dialogs & Transient Overlays (must redesign, same functions)

| Dialog | Trigger | Content & Actions |
| --- | --- | --- |
| **Delete routine** | Card swipe/button/menu/Edit Delete | Title “Delete routine?”; explains soft delete + recovery via Alarm Logs; Cancel / Delete |
| **Recover routine** | Logs/History Recover | “Recover routine?” with name; Cancel / Recover |
| **Reset today’s counter** | Summary / long-press menu | Explains zeroing today’s count; Cancel / Reset |
| **Count toward daily counter?** | Dismiss Early (Skip) | Cancel / No / Yes |
| **Adjust today’s max** | Swipe/button/menu | Message + numeric field with − / +; Cancel / Set (val ≥ 0) |
| **Unsaved changes** | Duplicate with dirty form | Message with routine name; Cancel / Discard & Continue / Save & Continue |
| **Routine card actions menu** | Long-press card | Title = routine name; Mute|Unmute, Pause|Resume, Dismiss Early, Adjust Today’s Max, Reset Today’s Counter, Edit, Duplicate, Delete |
| **Side button action picker** | Settings | Radio None / Snooze / Dismiss |
| **Swipe action picker** | Settings | Radio of five swipe actions |
| **Card button action picker** | Settings | Same five actions |
| **Export string** | Settings Export | Selectable base64; Copy / Close |
| **Import paste** | Settings Import | Multiline paste; Import / Cancel |
| **No routines to export** | Snackbar | Informational coral-style messaging (tone open in redesign) |
| **Import failed** | Snackbar | Retry guidance |
| **Day Start Time picker** | Edit form | Bottom sheet or time picker titled “Day Start Time”; Cancel / confirm draft time |
| **Duration fields** | Edit Interval/Snooze | Hours / Minutes / Seconds steppers + tap-to-type; min 1s; max < 24h |

---

### 2.10 Home Screen Widget (OS surface, optional companion)
Not an in-app route; must be considered for system parity.

**Required Data (per configured routine instance)**
- Routine name
- Next alarm **absolute clock time** (`hh:mm a` or `--:--`)
- Interval label
- Dismissals today (count for current day period)

---

## 3. Global UI Components & States

### Recurring chrome
- **Page scaffold:** title AppBar, optional leading/actions, safe body, optional FAB
- **Form sections:** labeled groups of fields/tiles
- **Section labels:** small headings within groups
- **Primary / secondary / destructive buttons**
- **Dialog buttons** (text actions)
- **Radio groups** (single select with optional subtitle)
- **Toggles**, **number steppers**, **duration triple control**, **volume control**, **sound row**, **weekday chips**, **time-of-day field**
- **Summary/settings tiles:** muted micro-label over value, tappable
- **Status message block:** icon + title + message + optional Retry / tappable icon CTA
- **Async list body:** Loading → Empty → Error(Retry) → List with fade between
- **Log entry tile:** action accent bar, action name, optional Muted, optional routine name, timestamp, optional duration or Recover
- **Press/haptic feedback** on primary taps (functional requirement: affirmative tactile feedback)
- **Live countdown** with tabular digits (HH:MM:SS), urgency escalation as remaining decreases
- **Slide-to-confirm tracks** (ring layout mode)

### Cross-cutting empty / loading / error copy (retain meaning)
| Surface | Empty | Error |
| --- | --- | --- |
| Home | No Routines Yet | Could Not Load Routines |
| Logs | No Log Entries Yet | Could Not Load Logs |
| History | No History Yet | Could Not Load History |
| Sound picker | No device sounds / No matches | (loading spinner) |
| Summary missing routine | Routine unavailable | n/a |

### Routine lifecycle actions (available from multiple entry points)
| Action | Effect (functional) |
| --- | --- |
| Mute / Unmute | Mute: schedule continues, fires silent auto-dismiss and still count; Unmute keeps next fire |
| Pause / Resume | Pause freezes countdown / cancels OS; Resume restores remaining or day-start rules |
| Dismiss Early (Skip) | Idle skip; retarget next ≈ now + interval (+ daily/weekday filters); optional daily count |
| Adjust Today’s Max | Sets effective max for current day period via extra allowance |
| Reset Today’s Counter | Zeros today’s count; may free alarm from day-start park if cap had blocked |
| Duplicate | Clone config + seed new schedule; opens edit for copy (from editor) or adds card (from menu) |
| Soft Delete | Remove from list, cancel alarms; recoverable from Delete logs |
| Recover | Restore + schedule again |
| Preview | Temporary ring UI only |

### Data model summary (what must be representable, not DB schema)

**Routine (config)**  
Name, IntervalSeconds, SnoozeSeconds, MaxTimesPerDayEnabled, MaxTimesPerDay, DayStartSeconds, EnabledWeekdays, DriftCompensationType, Vibrate, Volume (5–100), FadeIn, AudioUri/Sound, IsActive

**Routine state (live)**  
NextTriggerTime, InitialRingTime, CurrentSnoozeCount, TimesRingToday / TimesRingDay / ExtraMaxTimesToday, IsRinging, PausedAt, MutedAt, LastDismissedAt

**Log entry**  
RoutineId, Timestamp, LogActionType, TimeSinceLastDismissalSeconds?, WasMuted

**App settings**  
Theme Dark/Light; Ring layout Sliders/Buttons; VolumeUp/Down actions; Swipe Left/Right actions; Card bottom L/R actions

### Mental model microcopy for redesign consistency
- Alarms **roll forward**; not fixed HH:MM schedules
- **Day Start Time** is period boundary / parking point for caps and disabled weekdays, not “alarm at”
- **Snooze** delays without re-counting daily rings
- **Classic Interval** vs **Actual Dismissal** must remain selectable with clear naming

---

## 4. Verification Checklist (routing & coverage)

Cross-checked against `lib/main.dart`, `lib/navigation/routes.dart`, and page entry points:

| # | Surface | Entry | Blueprint section |
| --- | --- | --- | --- |
| 1 | Home | `MaterialApp.home` | 2.1 |
| 2 | Settings | Home AppBar | 2.8 |
| 3 | Alarm Logs | Home AppBar | 2.7 |
| 4 | New Routine | Home FAB / empty CTA | 2.4 |
| 5 | Edit Routine | Summary, card menu, tile deep-link | 2.4 |
| 6 | Routine Summary | Card tap (not ringing) | 2.6 |
| 7 | Summary History tab | Tab | 2.6 + log tiles |
| 8 | Alarm Sound Picker | Edit sound field | 2.5 |
| 9 | Alarm Ring live | OS fire / card when ringing | 2.2 |
| 10 | Alarm Ring preview | Edit Preview | 2.3 |
| 11 | Delete dialog | Multi | 2.9 |
| 12 | Recover dialog | Logs/History | 2.9 |
| 13 | Skip count dialog | Dismiss Early | 2.9 |
| 14 | Adjust max dialog | Multi | 2.9 |
| 15 | Reset counter dialog | Summary/menu | 2.9 |
| 16 | Unsaved changes | Duplicate dirty | 2.9 |
| 17 | Card actions menu | Long-press | 2.9 |
| 18 | Settings sub-pickers (×3) | Settings tiles | 2.9 |
| 19 | Import / Export dialogs | Settings | 2.8–2.9 |
| 20 | Home widget fields | OS | 2.10 |
| 21 | Duration / time pickers | Edit fields | 2.9 |

No bottom-nav routes or fixed clock-alarm screens exist in code. Non-UI concerns (permissions, OS reconciles) are out of scope for Stitch screens.

---

## 5. Visual Direction & Constraints

This section is complete. Stitch must apply it as the sole visual system. Do not invent an alternate brand style.

### Brand
- **Product name:** Rolling Alarm
- **Brand personality / vibe:** Quiet instrument panel. Calm and precise when idle or counting down. Only the ring surface becomes urgent and commanding. Feels like a reliable field timer for habits and medication, not a playful consumer toy, not a social app, not a glassmorphic dashboard wall.
- **Brand-first home signal:** AppBar wordmark “Rolling Alarm” is the primary identity on Home. No competing hero headline. Routine cards carry the functional content under that brand chrome.
- **Voice & tone (copy):** Short, direct, non-technical to the user. Prefer “Dismiss Early”, “Today’s counter”, “day start”, “every day”. No jokes. No emoji. No marketing fluff on empty states beyond one clear next step.

### Theme mode
- **Primary mode for redesign:** Design **both Light and Dark**, with Dark as the default showcase set (alarm use at night). Light is a true paper variant of the same system, not a separate aesthetic.
- **Contrast / accessibility floor:** Body text WCAG AA minimum vs surfaces. Countdown digits and ring action labels meet AAA-ish large text contrast where possible. Never place light coral text on pale paper without enough weight. Minimum touch targets 48dp.

### Color system (tokens)

**Dark (default)**
| Token | Hex | Use |
| --- | --- | --- |
| bg | `#0C0F12` | App background (near-black graphite, slight cool cast) |
| surface | `#161B21` | Elevated surfaces, dialogs, list rows |
| surfaceRaised | `#1E262E` | Cards under active countdown emphasis |
| textPrimary | `#E8EEF2` | Titles, routine names, values |
| textMuted | `#8B9AAb` | Labels, captions, secondary timestamps |
| textFaint | `#5C6B7A` | Disabled days, de-emphasized chrome |
| accent | `#2EC4A6` | Primary actions, Save, healthy countdown, active armed border, FAB |
| accentOn | `#04120F` | Ink on accent fills |
| urgent | `#FF5A4E` | Ringing, dismiss, delete, error emphasis |
| urgentSoft | `#FF5A4E` at ~15–25% fill / glow for ring atmosphere |
| sleep | `#6B7C9C` | Paused, muted, Auto Snooze–adjacent calm cool steel |
| recover | `#3DCF9A` | Recover actions, restore success |
| border | `#2A3440` | Hairline borders, dividers |
| divider | `#222A33` | Tab bar / section rules |

**Light (companion)**
| Token | Hex | Use |
| --- | --- | --- |
| bg | `#F3F5F4` | Soft cool paper (not warm cream) |
| surface | `#FFFFFF` | Elevated |
| surfaceRaised | `#E9EEE9` | Selected / armed surfaces |
| textPrimary | `#12181E` | Body titles |
| textMuted | `#5A6774` | Labels |
| textFaint | `#8A96A2` | Faint |
| accent | `#0F8F78` | Same role as dark, slightly deeper for paper contrast |
| accentOn | `#F4FFFB` | Ink on accent |
| urgent | `#D63A32` | Same roles as dark |
| sleep | `#5B6A86` | Pause / mute |
| recover | `#1FA873` | Recover |
| border | `#D0D8DE` | Borders |
| divider | `#E2E8EC` | Dividers |

**Do not use:** purple-to-indigo gradients, neon pink, pure pure-black glow stacks as the whole identity, glass blur chaos, or warm beige “editorial newspaper” grids.

### Color semantics by routine phase
- **Counting down / armed:** accent border or left rail; countdown color starts accent and shifts toward urgent as remaining becomes critical (under ~5 minutes lean warmer/urgent).
- **Ringing:** urgent everywhere (title, icon, border, ring frame). Snooze tracks or buttons use accent; Dismiss uses urgent.
- **Muted:** sleep border + sleep mute glyph; dimmed opacity of card body (~0.85).
- **Paused:** sleep border; dimmed (~0.62) + pause icon by status row.
- **Idle / not scheduled / error:** quiet border; error uses urgent soft text “Unavailable”.

**Log action accents (distinct but family-coherent):** map each log type to a single solid accent chroma (teal for Snooze, coral for Dismiss, steel for Auto Snooze and Mute, moss for Create/Recover, ochre for Pause, amber for Reset Counter). Keep chroma saturated enough to skim a long list.

### Typography
- **Display / ring title / brand wordmark:** **Space Grotesk** (or close geometric sans), weights 600–700. Slightly tight tracking on “ALARM RINGING” label; open tracking avoided beyond 5%.
- **UI body / labels / form fields:** **DM Sans**, weights 400 / 500 / 600.
- **Tabular numerals (countdown, clock, volume %, interval digits):** **IBM Plex Mono** or **JetBrains Mono**, tabular lining figures mandatory so digits do not jitter second-to-second.
- **Type scale (approx mobile):**
  - xs 11–12: micro labels, weekday letters, muted captions
  - sm 13–14: log titles, tile values, button labels
  - md 16–17: routine name on cards, form values
  - lg 20–22: AppBar titles
  - xl 28–32: live clock on ring
  - display 36–44: routine name on ring; 56–64 optional giant countdown elsewhere if used
- **No Inter, Roboto, Arial, or system UI default as the branded face.**

### Shape, density, composition
- **Corner radius:** 12dp for primary surfaces and dialogs; 8dp for dense chips (weekdays, steppers); 4dp for accent rails on log tiles. Avoid rounded-full pills for primary actions.
- **Spacing base:** 8dp grid. Common padding 16 body, 24 between major form sections.
- **Touch targets:** min 48×48dp.
- **Cards vs lists:** Home routines are distinct elevated list items (clear interactable units). Settings and Summary prefer **sectioned groups** of tiles without stacked “floating card walls.” Hero of any screen is never a collage of inset media cards.
- **Background atmosphere:** Dark uses subtle vertical gradient bg `#0C0F12` → `#11161C` (almost imperceptible). Light uses flat paper with a hairline top AppBar shadow only. No photographic full-bleed backgrounds on utility screens. Ring screen may use full-bleed dark field with soft urgent radial glow behind icon only (no stickers, no floating badges).
- **Density:** Comfortable, not sparse. List screens should show ~3–5 routine cards above the fold on a typical phone when content exists.

### Motion (design as intentional states)
1. **Page enter:** soft 220–280ms fade (secondary screens); ring enter short fade + scale 0.96→1.
2. **Ring urgency:** steady pulse cycle ~780ms on alarm icon scale/glow; escalation ramps over ~30–40s of ignoring (larger glow, denser border) without frenetic flicker.
3. **Countdown:** digits update every second with no layout shift (tabular mono); color blend 200–300ms when crossing urgency bands.
4. **Card swipe:** content translates with solid color reveal behind showing action icon; snap 180–220ms.
5. **Async lists:** crossfade loading ↔ empty ↔ list.

### Iconography & empty states
- **Icons:** outlined Material-style or similar geometric outline set; 1.5–2px stroke feel; no 3D or emoji.
- **Empty states:** single large outline icon (alarm_add, history_toggle_off, music_off, search_off) + title + one short sentence + optional primary CTA on Home. No illustrations of mascots.
- **Widget (OS):** compact, high-legibility clock time dominant, name second line, interval and dismissals as supporting meta, match dark graphite / accent system where OS allows.

### Platform & layout constraints
- **Platform:** Android phone, **portrait primary**
- **Ring UI:** primary actions (snooze/dismiss) in lower third for one-hand reach; safe-area aware for gesture nav.
- **App shell:** sticky top AppBar per screen; no bottom navigation bar; no side drawer.
- **Text scaling:** designs should still work at 1.0–1.2 system scale without clipping AppBar titles (ellipsis ok).
- **Do not invent:** fixed daily wall-clock alarm modes, multi-user accounts, social feeds, web desktop layouts, marketing landing pages, onboarding carousels, dashboards with stats strips of unrelated KPIs.

### Deliverables (what Stitch must generate)
Generate a **complete mobile screen set** for **Dark and Light**, portrait, covering **every** item below:

**Primary screens**
1. Home empty
2. Home with multiple routine cards showing mixed phases (counting down, muted, paused, ringing)
3. Settings (full scrollable: all sections visible across frames as needed)
4. Alarm Logs empty
5. Alarm Logs populated (including Recover on a Delete row)
6. New Routine (empty form, validation error example on Name)
7. Edit Routine (filled form + Duplicate/Delete footer)
8. Alarm Sound Picker (Silent, Default, device list, search)
9. Routine Summary → Summary tab
10. Routine Summary → History tab
11. Alarm Ring live, **Sliders** layout
12. Alarm Ring live, **Buttons** layout
13. Alarm Ring preview (can share ring visual language)

**Dialogs / sheets (each as modal on dimmed parent)**
14. Delete routine
15. Recover routine
16. Reset today’s counter
17. Count toward daily counter?
18. Adjust today’s max (stepper)
19. Unsaved changes
20. Routine card actions menu
21. Side button action picker
22. Swipe action picker
23. Card button action picker
24. Export RA1 string
25. Import paste

**Companion**
26. Android home widget (single routine instance)

**Priority order if generating in batches:** Home armed list → Alarm Ring (both layouts) → New/Edit Routine → Summary → Settings → Logs → all dialogs → Sound picker → Widget.

---

## 6. Stitch generation instruction (use as system directive)

You are redesigning **Rolling Alarm**, an Android interval-based recurring alarm app.

1. Build every screen, dialog, and component listed in Sections 2, 3, and 5 of this document.
2. Preserve **exact information architecture, fields, actions, empty/error copy intent, and navigation** from Sections 1–3.
3. Apply **only** the visual system in Section 5 (colors, type, radius, motion, density). Do not reuse legacy app screenshots or invent purple/gradient/glass “AI default” themes.
4. Do not add features, screens, or product modes outside this blueprint (no fixed clock alarms, no social, no multi-user).
5. Produce high-fidelity mobile UI frames for Dark **and** Light across the full deliverable list in Section 5.
6. On every design, the functional checklist for that screen in Section 2 must remain obviously satisfied (e.g. Home still shows name, interval, phase status, countdown, today count, weekdays strip when needed, swipe actions, card buttons, FAB, settings, logs).
