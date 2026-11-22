# Rolling Alarm

**Package name:** `rolling_alarm`  
**Application ID:** `com.casellaweb.rolling_alarm`  
**Version:** `1.1.0+5` (version name `1.1.0`, version code `5`)  
**Publisher:** Casella Web  
**Platform:** Android only  
**Repository:** https://github.com/MrJames12345/RollingAlarm  

This document is the full product and engineering overview of Rolling Alarm: purpose, architecture, setup, data model, alarm math, native reliability stack, UI, testing, and shipping. Deeper algebra for next fire times also lives in [`docs/features-and-alarm-time-logic.md`](docs/features-and-alarm-time-logic.md). UI redesign detail lives in [`docs/stitch-ui-blueprint.md`](docs/stitch-ui-blueprint.md).

---

## Table of contents

1. [What this app is](#1-what-this-app-is)
2. [What this app is not](#2-what-this-app-is-not)
3. [Tech stack](#3-tech-stack)
4. [Repository layout](#4-repository-layout)
5. [How the app starts](#5-how-the-app-starts)
6. [Architecture](#6-architecture)
7. [Alarm time logic](#7-alarm-time-logic)
8. [Dual scheduling and native wake path](#8-dual-scheduling-and-native-wake-path)
9. [Data model and persistence](#9-data-model-and-persistence)
10. [Features in detail](#10-features-in-detail)
11. [UI, navigation, and theming](#11-ui-navigation-and-theming)
12. [Permissions and Play policy](#12-permissions-and-play-policy)
13. [Home screen widget](#13-home-screen-widget)
14. [Import, export, and PDF](#14-import-export-and-pdf)
15. [Settings](#15-settings)
16. [Conventions and naming](#16-conventions-and-naming)
17. [Build, run, and develop](#17-build-run-and-develop)
18. [Testing](#18-testing)
19. [Release and Google Play](#19-release-and-google-play)
20. [Alternate entry points and tooling](#20-alternate-entry-points-and-tooling)
21. [Related documentation](#21-related-documentation)
22. [Known follow ups](#22-known-follow-ups)

---

## 1. What this app is

Rolling Alarm is an **interval based recurring alarm** app for Android. Users create **routines**. Each routine fires repeatedly every N hours or minutes. After the user Dismisses, Skips, Snoozes, or ignores the ring long enough for Auto Snooze, the next fire time is recalculated from that interval. The schedule rolls forward from the action, not from a fixed wall clock slot like "every day at 7:00".

Typical use cases:

- Medication dose intervals every N hours
- Rotating and FIFO shift rosters
- ADHD routine loops (stretch, hydrate, focus, stand)
- Caregiving or patient check intervals
- Any task that must recur on a duration, not a clock face time

The product is offline-first and keeps all routines and logs strictly on the device. There is no account system, no cloud sync, and no analytics/tracking backend. State is SQLite via Drift, plus SharedPreferences for settings and cross-isolate keys. Optional Rolling Alarm Pro upgrades are handled via Google Play Billing through RevenueCat (`RA_PurchaseService`, offline-first with cached entitlement fallback).

---

## 2. What this app is not

- Not a one shot timer
- Not a fixed "alarm at HH:MM every day" clock
- Not a random or rolling time window scheduler
- Not multi user or cloud backed
- Not available on iOS, web, Windows, macOS, or Linux (no those platform trees exist)
- Not dependent on Flutter local notifications for the primary ring UX (the ring is a full screen page plus a native foreground service)

Day Start Time exists only as a daily period boundary and parking point when the daily cap or weekday rules apply. It is not a classic fixed daily alarm time.

---

## 3. Tech stack

| Layer | Choice |
| --- | --- |
| Language | Dart (SDK `^3.8.0`), Kotlin on Android |
| UI | Flutter Material, Google Fonts (bundled offline via `assets/fonts/`, runtime fetching disabled) |
| State | `flutter_riverpod` (AsyncNotifiers, StreamProviders) |
| Database | Drift + SQLite (`sqlite3_flutter_libs`), WAL mode, schema version **18** |
| Prefs | `shared_preferences` |
| Dart alarms | `android_alarm_manager_plus` (background isolate callback + watchdog) |
| Native alarms | Custom Kotlin `AlarmManager.setAlarmClock` via `AlarmUiSchedulerPlugin` + `AlarmSqliteGate` read-only guard |
| Notifications | `flutter_local_notifications` (legacy channel, FSI permission helpers; not the primary ring surface) |
| Audio | Permissionless `RingtoneManager` + `ACTION_OPEN_DOCUMENT` (`just_audio` + `audio_session`, plus native `AlarmRingtonePlayer`) |
| Vibration | Dart service + native `AlarmVibrator` |
| Permissions | Contextual `RA_PermissionService` (`permission_handler` + native status queries) |
| Billing / Pro | `purchases_flutter` (RevenueCat v11, offline-first `RA_PurchaseService` + Drift v18 grandfathering) |
| Home widget | `home_widget` + Jetpack Glance |
| PDF / share | `pdf` + `printing` |
| Files / links | `file_picker`, `url_launcher` |
| Tests | `flutter_test`, `mocktail`, `integration_test`, `patrol`, `sqlite3` |
| Codegen | `drift_dev` + `build_runner` |
| Android tooling | AGP `9.0.1`, Kotlin `2.3.20`, Java 17, Compose for Glance, desugaring |

Dependency versions are pinned with caret constraints in `pubspec.yaml`; resolved versions are in `pubspec.lock`.

---

## 4. Repository layout

```
RollingAlarm/
├── lib/                          Flutter app source
│   ├── main.dart                 Production entry
│   ├── main_screenshots.dart     Play Store screenshot seeding entry
│   ├── main_permission_demo.dart Permission demo recording entry
│   ├── styles.dart               Theme tokens (colours, text, shapes)
│   ├── utils.dart                Formatting helpers + RA_tryAsync
│   ├── navigation/routes.dart    Imperative Navigator helpers + navigatorKey
│   ├── providers/providers.dart  Riverpod wiring
│   ├── database/                 Drift DB, tables, generated .g.dart
│   ├── enums/                    Domain enums
│   ├── models/                   Hand written models (e.g. alarm_sound)
│   ├── pages/                    Screens (*Page)
│   ├── components/               RA_ widgets (common / field / routine)
│   └── services/                 RA_*Service static services
├── android/                      Native Android (Kotlin + Glance widget)
├── assets/audio/                 Default alarm tone
├── assets/branding/              Logos / brand assets
├── assets/fonts/                 Bundled fonts (offline Google Fonts)
├── test/                         Unit and widget tests
├── integration_test/             Device integration + screenshots
├── patrol_test/                  Patrol bundle
├── scripts/                      Run, screenshot, adb, demo helpers
├── docs/                         Product and policy documentation
├── dbMigrations/                 Reference SQL snippets (not auto applied)
├── screenshots/                  Pulled Play / QA PNGs
├── #GooglePlay/                  Play listing helpers (`translations.csv`, `release-notes-1.1.0.xml`)
├── #Backup/                      Design image backups
├── play-policy-audit.md          Historical 1.0.0 Play permission audit
├── release-1.0.1-changes.md      1.0.1 changelog and verification notes
├── run.bat                       Emulator launch + flutter run
└── pubspec.yaml
```

### Important Dart modules

| Path | Role |
| --- | --- |
| `lib/main.dart` | Init bundled fonts, DB path, AlarmManager, notifications, `RA_PurchaseService` + grandfathering sync, reconcile, log prune, `ProviderScope` |
| `lib/services/alarm.dart` | Schedule, fire isolate, transitions, pause/mute (disarms native UI when muted), reconcile |
| `lib/services/alarm_calculator.dart` | Pure next trigger math |
| `lib/services/daily_ring_limit.dart` | Cap, day periods, create/edit retarget |
| `lib/services/weekday_schedule.dart` | Enabled day bitmask + deferral |
| `lib/services/permissions.dart` | `RA_PermissionService`: contextual alarm permissions + live reliability status |
| `lib/services/purchase.dart` | `RA_PurchaseService`: offline-first RevenueCat Pro, 24h Day-0 Founding Lifetime timer, v1.0.1 grandfathering resolution, widget/prefs sync |
| `lib/services/notification.dart` | Ringing prefs + FSI permission (+ legacy channel) |
| `lib/services/audio.dart` / `vibration.dart` | Playback / vibrate |
| `lib/services/settings.dart` | Theme, layout, swipe/side/card button prefs |
| `lib/services/export.dart` | `RA1:` base64 import/export (v10) |
| `lib/services/pdf.dart` | Log history PDF share (background isolate) |
| `lib/services/widget.dart` | Home widget data bridge |
| `lib/services/alarm_sound_picker.dart` | Permissionless `RingtoneManager` device sounds + `ACTION_OPEN_DOCUMENT` local audio picker |
| `lib/services/routine_duplicate.dart` | Duplicate a routine |
| `lib/models/routine_template.dart` | Curated 1-tap Quick-Start routine presets |
| `lib/database/database.dart` | Drift schema v18 (`AppMeta` grandfathering, `countLiveRoutines`, `pruneOldLogs`, CAS updates) |
| `lib/components/common/alarm_ring_presenter.dart` | Forces `AlarmRingPage` above all routes, syncs effective Pro, handles native widget paywall bridge |
| `lib/pages/*` | Home, edit, ring, summary, logs, settings, sound picker, paywall (`PaywallPage`) |

### Important Kotlin modules

| Path | Role |
| --- | --- |
| `MainActivity.kt` | Lock screen flags, permissionless `RingtoneManager` listing & `ACTION_OPEN_DOCUMENT` audio picker, side-button & `paywall` MethodChannels |
| `AlarmUiSchedulerPlugin.kt` | `setAlarmClock` schedule/cancel, manual battery exemption & permission status queries, vibration, widget refresh |
| `AlarmSqliteGate.kt` | Read-only SQLite guard (`rolling_alarm.db`) suppressing native wake/ring/resurrection for deleted, paused, or muted routines |
| `AlarmReceiver.kt` | Exact alarm broadcast → `AlarmSqliteGate` check → FGS + activity launch |
| `AlarmRingingService.kt` | Foreground ringing service (`systemExempted`), `AlarmSqliteGate` check, FSI notification |
| `AlarmRingtonePlayer.kt` / `AlarmVibrator.kt` | Native audio / vibrate |
| `AlarmResurrectionReceiver.kt` | Boot / package replaced native re-arm (filtered by `AlarmSqliteGate`) |
| `RollingAlarmGlanceWidget.kt` + `WidgetConfigActivity.kt` | Home widget UI + routine picker (enforces Free 1-widget cap with Pro bridge to `MainActivity`) |
| `AlarmRingDisplayGate.kt` | Suppress display wake after user locks mid ring |

---

## 5. How the app starts

Cold start order in `lib/main.dart`:

1. `WidgetsFlutterBinding.ensureInitialized()` and `GoogleFonts.config.allowRuntimeFetching = false` (uses bundled `assets/fonts/` with zero network font fetches)
2. `RA_Database.resolveDatabasePath()` → `{appDocuments}/rolling_alarm.db`
3. `RA_AlarmService.persistDatabasePath(dbPath)` into SharedPreferences (`ra_db_path`) so background isolates and `AlarmSqliteGate` can open Drift
4. Construct `RA_Database()`, bind it to the notification service
5. Register a UI isolate receive port (`ra_alarm_port`) so the alarm isolate can ping table updates
6. `RA_AlarmService.init()` → `AndroidAlarmManager.initialize()`
7. `RA_NotificationService.init()`
8. `RA_PurchaseService.init()` → hydrates `ra_first_seen_epoch_ms` and cached RevenueCat Pro state (`ra_rc_is_pro_cached`), lazily configures RevenueCat if `REVENUECAT_ANDROID_API_KEY` was supplied at build time (never blocks cold start), reads Drift v18 `isLegacyProGrandfathered()`, and syncs effective Pro status to SharedPreferences + HomeWidget
9. `reconcileAlarmsOnStartup` re-arms from Drift (covers force-stop / missed reboot restore)
10. Unawaited `database.pruneOldLogs()` (trims logs older than 365 days while preserving recoverable soft-deleted routine `Delete` rows)
11. Lock portrait orientation, load theme, `runApp(ProviderScope(... RollingAlarmApp))`

**No cold-start permission bombing:** `main.dart` does not prompt for permissions on launch. Core alarm permissions are requested contextually via `RA_PermissionService.ensureCoreAlarmPermissions` when the user creates, imports, duplicates, resumes, or recovers a routine, while OEM battery/overlay controls live under Settings → Alarm Reliability.

After the first frame, `RA_AlarmRingPresenter` calls `syncAlarmUiSchedules` once the Flutter engine and MethodChannel are live, so native `setAlarmClock` entries match Drift (and muted routines remain disarmed natively).

There is no `.env` file. Optional RevenueCat Android billing is configured at release build time via `--dart-define=REVENUECAT_ANDROID_API_KEY=...`; when blank or offline, `RA_PurchaseService` fails soft with cached entitlements and AUD fallback display pricing.

Release signing uses `android/key.properties` and a keystore file. Both are gitignored.

---

## 6. Architecture

### Layers

```
UI (pages / components + Riverpod)
        │
        ▼
RA_AlarmService  ◄── RA_AlarmCalculator / RA_DailyRingLimit / RA_WeekdaySchedule
        │
        ├── Drift (Routines / RoutineStates / LogEntries / AppMeta)
        ├── SharedPreferences (settings, db path, ringing & effective Pro flags)
        ├── android_alarm_manager_plus (Dart isolate callback + watchdog)
        └── MethodChannel → setAlarmClock → AlarmReceiver (guarded by AlarmSqliteGate)
              → AlarmRingingService → MainActivity (full screen intent)
```

**Source of truth for the next fire:** `RoutineStates.NextTriggerTime`. OS timers are always rearmed from that value. Scheduling never invents a new time by itself; it only arms (and clamps past times to roughly `now + 1s`).

### Why dual scheduling

On `scheduleNext`:

1. **Dart path:** `AndroidAlarmManager.oneShotAt` with `exact`, `wakeup`, `allowWhileIdle`, `rescheduleOnReboot`. This runs `_alarmCallback` in a background isolate for Drift state, counting, logging, audio fallback, and UI ping.
2. **Native path:** `setAlarmClock` via `AlarmUiSchedulerPlugin`. This drives the status bar clock affordance, starts the foreground ringing service, and launches the full screen intent even if the Flutter process was killed.

Both paths exist because OEM battery policies are aggressive. Either path alone can miss or truncate rings on some devices; together they cover Dart state work and OS level wake UX.

### Cross isolate coordination

- DB path stored in prefs for headless opens (`RA_Database.openForIsolate`)
- UI port name `ra_alarm_port` for table update pings
- Compare and swap writes on `updateRoutineState` (`requireIsRinging`, optional `matchNextTriggerTime`) prevent double fire races between UI and alarm isolates

### Fire path (simplified)

1. OS fires → native receiver/service wakes UI and/or Dart `_alarmCallback`
2. Fresh cycle gates: deleted/inactive, weekday, daily cap, mute
3. Else: set `IsRinging`, log `Ring`, set ringing prefs, arm auto snooze watchdog, start audio if native is not already playing, ping UI
4. `RA_AlarmRingPresenter` pushes `AlarmRingPage`
5. User or system transition → `handleTransition` → calculator (+ daily/weekday filters for Dismiss/Skip) → persist → `scheduleNext`

---

## 7. Alarm time logic

Authoritative deep dive: [`docs/features-and-alarm-time-logic.md`](docs/features-and-alarm-time-logic.md). Summary below.

### Mental model

Three pure layers compute times, then `RA_AlarmService` persists and arms the OS:

| Layer | File | Job |
| --- | --- | --- |
| Interval / action math | `lib/services/alarm_calculator.dart` | Dismiss, Snooze, Skip, AutoSnooze |
| Daily cap + day start | `lib/services/daily_ring_limit.dart` | Cap, period boundaries, create/edit retarget |
| Weekdays | `lib/services/weekday_schedule.dart` | Enabled days + deferral |
| Orchestration | `lib/services/alarm.dart` | Fire, count, pause/resume/mute, OS schedule |

### Base formulas (`RA_AlarmCalculator`)

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

**Actual Dismissal** lets snooze time add drift into the next cycle.  
**Initial Ring (Classic Interval)** absorbs snooze time and keeps the classic interval grid from the first ring of the cycle.

### Post filters (Dismiss and Skip only)

Snooze and AutoSnooze skip both filters.

```
next =
  deferToEnabledDay(
    deferIfDailyLimitReached(calculated, …),
    EnabledWeekdays,
    dayStartSeconds
  )
```

**Daily cap:** if the feature is off, proposed is unchanged. Otherwise:

1. If proposed reaches or passes next day start → park at that day start
2. If today's fresh ring count is at or over max → park at next day start
3. Else keep proposed

A "day" is `[dayStart, dayStart + 24h)`, not calendar midnight unless `DayStartSeconds == 0`.

**Weekdays:** Monday first bitmask (`EnabledWeekdays`, default `127` = all days). If today's weekday is disabled, walk forward and land on the next enabled day at the Day Start Time clock, not at the original proposed time of day. A zero mask is treated as all days. The UI cannot turn off the last remaining weekday.

### Where next fire time is set

| Event | What happens |
| --- | --- |
| Create / Import | Cap on → next Day Start; cap off → `now + interval`; then weekday deferral |
| Edit | Only retargets for certain cap / day start boundary cases; interval alone applies next cycle |
| Dismiss / Skip | Calculator → daily → weekday → schedule |
| Snooze / Auto | `now + snooze` only |
| Fire blocked | Weekday defer or next day start (+ weekday), no ring |
| Muted fire | Same as Dismiss path, silent, still counts |
| Pause | If ringing, dismiss style next; freeze remaining (day start targets stay absolute) |
| Resume | Restore remaining, or sooner of interval vs next day start if day start was missed |
| Reset today's counter | Count = 0; if previously capped and parked on day start, unpark to `now + interval` |
| Soft delete | `NextTriggerTime = null`, cancel OS timers |
| Startup | Re arm stored `NextTriggerTime` (clamp if past) |

### What counts toward the daily cap

- Fresh ring at trigger (before UX)
- Optional idle Skip when the user says yes
- Muted fresh fires
- Snooze re rings do **not** count again

`ExtraMaxTimesToday` (schema v17) lets the user temporarily raise today's effective max via "Adjust Today's Max" without changing the base `MaxTimesPerDay`.

### Timezone and DST

No timezone package. Math uses device local `DateTime` duration addition. Spring forward / fall back behave as naive duration addition.

---

## 8. Dual scheduling and native wake path

### Dart isolate (`android_alarm_manager_plus`)

- One shot exact wakeup for each next fire
- Separate auto snooze watchdog one shot while ringing
- Callback updates Drift, logs, may start Dart audio, pings UI port
- Plugin reboot receivers also listen for OEM quick boot actions

### Native `setAlarmClock` path

```
AlarmUiSchedulerPlugin.schedule
  → AlarmManager.setAlarmClock
  → AlarmReceiver.onReceive (partial wake lock bridge + AlarmSqliteGate check)
  → AlarmRingingService (FGS systemExempted + AlarmSqliteGate check + FSI notification + native audio/vibrate)
  → MainActivity launched full screen / show when locked
```

Reliability details hardened across 1.0.1 and 1.1.0:

- Receiver wake lock is allowed to self expire so the CPU stays awake until the service acquires its own lock
- Ringing service partial wake lock cap raised to 10 minutes (still released on dismiss/snooze)
- Boot resurrection refuses to wipe saved native alarm entries when exact alarm access is unavailable
- **`AlarmSqliteGate.kt` (v1.1.0):** Read-only SQLite guard against `rolling_alarm.db` checked in `AlarmReceiver`, `AlarmRingingService`, and `AlarmResurrectionReceiver` so deleted, paused, or muted routines are never woken or rung natively (fails open on transient storage errors so real alarms are never silenced)
- **Silent-mute scheduling (v1.1.0):** `muteRoutine` disarms native `setAlarmClock` (`_cancelAlarmUi`), `scheduleNext` and `syncAlarmUiSchedules` skip `_scheduleAlarmUi` while `MutedAt != null` (keeping only Dart `_alarmCallback` armed for silent auto-dismiss + counting), and `unmuteRoutine` re-arms `_scheduleAlarmUi` immediately
- **`scheduleNext` never prompts battery settings (v1.1.0):** Battery optimization exemption is strictly user-initiated from Settings → Alarm Reliability rather than invoked during alarm scheduling

### Startup and resurrection

- `AlarmResurrectionReceiver` on `BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`, and OEM quick boot intents
- Dart `reconcileAlarmsOnStartup` on every cold start
- `RA_AlarmRingPresenter` also has a foreground UI watchdog (~15s) and countdown `forceRingIfDue` so a live UI can recover a due alarm

### Notifications role

Alarms do **not** rely on Flutter local notifications for primary UX. `showAlarmNotification` mainly sets SharedPreferences ringing flags. The product surface is the full page ring + native FGS. The notification channel remains for cancel/permission APIs.

---

## 9. Data model and persistence

### SQLite file

Path: `{appDocuments}/rolling_alarm.db`  
Opened with WAL, busy timeout 5000, synchronous NORMAL.  
Schema version: **18** with stepwise `onUpgrade` migrations in `lib/database/database.dart`.  
`dbMigrations/*.sql` files are human reference notes; Drift owns real migrations.  
On startup, `pruneOldLogs()` removes soft-deleted logs and entries older than 365 days while preserving `Delete` rows for still-soft-deleted routines so recovery continues to work.

### Table: `Routines` (config)

| Field | Meaning |
| --- | --- |
| `Id` | Auto increment PK |
| `Name` | 1..255 chars |
| `SnoozeSeconds` | Snooze + auto snooze + watchdog length (default 300) |
| `IntervalSeconds` | Base cycle length |
| `MaxTimesPerDayEnabled` / `MaxTimesPerDay` | Optional daily fresh ring cap |
| `DayStartSeconds` | Seconds after local midnight for period boundary |
| `EnabledWeekdays` | Monday first bitmask |
| `DriftCompensationTypeCode` | ActualDismissal vs InitialRing |
| `ShowPreview` | Editor preview affordance |
| `Vibrate` | Vibrate while ringing |
| `Volume` | 5..100 |
| `FadeIn` | Fade from silent to volume |
| `AudioUri` | Nullable sound URI encoding |
| `IsActive` | Pause clears this |
| `CreatedAt` / `ModifiedAt` / `Deleted` | Audit + soft delete |

### Table: `RoutineStates` (live cycle)

One row per routine (`UNIQUE(RoutineId)`).

| Field | Meaning |
| --- | --- |
| `NextTriggerTime` | Scheduled fire instant (OS rearm source of truth) |
| `InitialRingTime` | Anchor for InitialRing compensation |
| `CurrentSnoozeCount` | `> 0` means snooze resume (preserve initial ring; don't re count) |
| `TimesRingToday` / `TimesRingDay` | Cap accounting for current day period |
| `ExtraMaxTimesToday` | Bonus toward today's effective max |
| `IsRinging` | Live ring; CAS guard for transitions |
| `LastDismissedAt` | Logging only |
| `PausedAt` | Freeze remaining = next minus this instant |
| `MutedAt` | Silent dismiss path on fire |
| Audit columns | Same soft delete pattern |

### Table: `LogEntries`

| Field | Meaning |
| --- | --- |
| `RoutineId` | Owning routine |
| `Timestamp` | Event time |
| `LogActionTypeCode` | See enum below |
| `TimeSinceLastDismissalSeconds` | Optional gap metric |
| `WasMuted` | Muted auto dismiss flag |
| Audit columns | Soft delete supported |

### Table: `AppMeta` (schema v18)

| Field | Meaning |
| --- | --- |
| `Key` | Primary key (`legacy_pro_grandfathered`) |
| `MetaValue` (`value`) | String value (`'true'` when upgrading from v17 with existing routines) |
| `UpdatedAt` | Timestamp |

### Log action codes

Aligned for 0..3 with alarm actions, then lifecycle events:

`Dismiss`, `Snooze`, `Skip`, `AutoSnooze`, `Create`, `Edit`, `Delete`, `Duplicate`, `Pause`, `Resume`, `Mute`, `Unmute`, `ResetCounter`, `Ring`, `Recover`

### SharedPreferences (selected keys)

| Key / family | Purpose |
| --- | --- |
| `ra_db_path` | Absolute DB path for isolates and `AlarmSqliteGate` |
| `ra_is_ringing` / related | Ringing coordination flags |
| `ra_first_seen_epoch_ms` | Day-0 first-launch timestamp for the 24-hour Founding Lifetime offer window |
| `ra_rc_is_pro_cached` | Offline cache of RevenueCat `'pro'` entitlement |
| `ra_is_pro_effective` / HomeWidget `ra_is_pro` | Combined effective Pro flag (`rcPro || legacyPro`) read synchronously by `WidgetConfigActivity` |
| `ra_perm_notif_prompted` / `ra_perm_fsi_prompted` | One-time contextual permission onboarding flags (`RA_PermissionService`) |
| Theme, layout, swipe, side buttons, card buttons | User settings via `RA_SettingsService` |
| Native private prefs | Cached schedules for resurrection / UI scheduler |

### Soft delete

Routines, states, and logs use `Deleted` flags. Soft deleted routines can be recovered from Logs / history. Recover restores rows and can reschedule.

---

## 10. Features in detail

### Routines CRUD & Quick-Start templates

- 1-tap Quick-Start templates (`RA_RoutineTemplates` / `RA_QuickTemplatesStrip` on empty `HomePage` and `RoutineEditPage`): Medication Cadence, Focus / Hydration Grid, WA FIFO / Night Shift, and Caregiver / Patient Check
- Create / edit: `pages/routine_edit.dart` → Drift insert/update + `RA_DailyRingLimit.initialTriggerTime` / `retargetNextAfterEdit` + `scheduleNext` + contextual `RA_PermissionService.ensureCoreAlarmPermissions`
- Soft delete / recover: `RA_Database.softDeleteRoutine` / `recoverRoutine` + alarm cancel / reschedule
- Duplicate: `services/routine_duplicate.dart`

### Rolling interval alarms

After a cycle ends (Dismiss or Skip), next fire is based on the interval. The only wall clock parking is Day Start when the daily cap or weekday deferral applies.

### Drift compensation

Two modes on Dismiss:

1. **Actual Dismissal:** `now + interval` (snooze adds drift)
2. **Initial Ring:** first ring of this cycle + interval grid (snooze absorbed)

### Snooze / Auto snooze

- Manual snooze from ring UI or side buttons
- Auto snooze watchdog: if ignored for `SnoozeSeconds`, system auto snoozes
- Unlimited snoozes
- Snooze does not increment the daily ring counter again

### Dismiss

Ends the ring cycle, recalculates next interval fire, resets snooze count, logs dismiss.

### Dismiss Early (Skip)

Idle skip of the pending next fire; retargets to `now + interval` (then daily / weekday filters). Prompts whether to count toward today's daily total. Available whenever the routine is not paused, including when next fire is already a day start ("Starts at") boundary.

### Daily ring limit

Optional max fresh rings per day period. When the cap is hit, or the next interval would cross the next day start, next fire snaps to next day start. Manual "Reset today's counter" zeros the count and can unpark a capped day start target.

### Enabled weekdays

Monday first bitmask. Disabled day proposals defer to next enabled day at Day Start Time.

### Pause / Resume

- **Pause:** cancel OS timers, `IsActive=false`, freeze remaining countdown (day start targets keep absolute time). Clears mute.
- **Resume:** restore remaining, or for a missed day start use the sooner of `now + interval` vs next day start. Then weekday deferral and schedule.

### Mute / Unmute

- Schedule keeps running; muted fires silently auto dismiss and still count
- `muteRoutine` disarms native `setAlarmClock` (`_cancelAlarmUi`), `scheduleNext` skips `_scheduleAlarmUi` while `MutedAt != null`, and `AlarmSqliteGate` guards native wake paths so muted routines never wake the screen or play audio
- Muting while paused clears pause first (resume then mute)
- `unmuteRoutine` does not change next fire time and immediately re-arms `_scheduleAlarmUi` for active routines

### Ring UI

- Full screen `AlarmRingPage` (sliders or buttons layout from settings)
- Volume side keys mapped via Settings → `MainActivity.dispatchKeyEvent` → MethodChannel `sideButtonAction`
- Preview from editor has no schedule side effects
- Live ring cannot be casually back dismissed the way a normal route can

### Logging

Global `LogsPage` plus per routine history on summary. Free tier views the last 7 days; Pro unlocks full 365-day history and printable PDF share via `RA_PdfService` (generated on a background isolate).

### Sounds

Permissionless audio pipeline (zero `READ_MEDIA_AUDIO` or storage manifest permissions): device default, system alarm & ringtone tones enumerated via Android `RingtoneManager` (`TYPE_ALARM` + `TYPE_RINGTONE`), system ringtone picker, or custom local audio files picked via `ACTION_OPEN_DOCUMENT` with persistable URI read permissions (`Pro`). Encoded in `RA_AlarmSound`. Bundled fallback: `assets/audio/default_alarm.mp3`. Volume and optional gentle fade-in (`Pro`) are per routine.

### Rolling Alarm Pro & v1.0.1 grandfathering

- `RA_PurchaseService` (`lib/services/purchase.dart`) wraps RevenueCat (`purchases_flutter` v11) offline-first with cached entitlements and a 24-hour Day-0 Founding Lifetime offer (`ra_first_seen_epoch_ms`).
- **Free forever:** Core rolling alarms, up to 2 live routines, 1 home screen widget, 7-day log history, Actual Dismissal mode, built-in and `RingtoneManager` device sounds.
- **Rolling Alarm Pro** (one-time Lifetime unlock, Annual, or Monthly): unlimited routines and home screen widgets, Classic Interval (Initial Ring) drift compensation, Adjust Today's Max, custom local audio files, gentle fade-in, hardware volume-key actions, full 365-day log history, printable PDF reports, and `RA1:` backups.
- **Automatic v1.0.1 grandfathering:** Devices upgrading from schema v17 to v18 with existing routines are permanently marked `legacy_pro_grandfathered = 'true'` in `AppMeta` and keep full Pro access automatically. Effective Pro (`IsProProvider`) is `rcPro || legacyPro`.

---

## 11. UI, navigation, and theming

### Navigation pattern

Single root `HomePage` + imperative `Navigator` + fade routes. No go_router, no bottom tabs, no drawer.

```
HomePage
  ├─ SettingsPage
  ├─ LogsPage
  ├─ PaywallPage (Rolling Alarm Pro upgrade / Founding offer)
  ├─ RoutineEditPage (create / edit / Quick Templates)
  │     └─ AlarmSoundPickerPage
  ├─ RoutineSummaryPage (details + history)
  └─ AlarmRingPage  (forced above stack by RA_AlarmRingPresenter)
```

Shared chrome: `RA_PageScaffold`, form fields under `components/field/`, dialogs under `components/common/`.

### Home card behaviour (high level)

- Tap (not ringing) → Summary
- Tap (ringing) → Ring page
- Swipe L/R → configurable actions (Mute / Pause / Dismiss Early / Adjust Max / Delete)
- Bottom L/R icon buttons → same action set
- Long press → actions menu dialog
- Live countdown toward `NextTriggerTime`, today's count, weekday strip when not every day

### Theme

Dark is the default. Light is available. Tokens live in `styles.dart` (`RA_ColourStyles`, `RA_AppTheme`, shape/glow helpers). Brand accents include sage teal, indigo, and coral tones. Google Fonts are used rather than the platform default stack alone.

Portrait only.

Full screen by screen functional blueprint for redesign work: [`docs/stitch-ui-blueprint.md`](docs/stitch-ui-blueprint.md).

---

## 12. Permissions and Play policy

### Manifest permissions (high level)

| Permission | Why |
| --- | --- |
| `SCHEDULE_EXACT_ALARM` (maxSdk 32) | Exact alarms on Android 12 / 12L |
| `USE_EXACT_ALARM` | Exact alarms on API 33+ for alarm clock apps |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | OEM kill resistance (Samsung / Xiaomi etc.) |
| `WAKE_LOCK` | Keep CPU awake through ring bridge / service |
| `RECEIVE_BOOT_COMPLETED` / `QUICKBOOT_POWERON` | Re arm after reboot / OEM quick boot |
| `POST_NOTIFICATIONS` | FGS / FSI notification channel |
| `USE_FULL_SCREEN_INTENT` | Full screen ring over lock screen |
| `VIBRATE` | Vibration while ringing |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_SYSTEM_EXEMPTED` | Ringing FGS type |
| `SYSTEM_ALERT_WINDOW` | Optional fallback (manually enabled in Settings → Alarm Reliability) when BAL blocks startActivity |
| `TURN_SCREEN_ON` / `DISABLE_KEYGUARD` | Wake / show over lock |

**Zero audio/storage permissions (v1.1.0):** `READ_MEDIA_AUDIO` and legacy external storage permissions were removed. System sounds come from permissionless `RingtoneManager`, and custom audio files use Android's Storage Access Framework (`ACTION_OPEN_DOCUMENT`) with persistable URI grants.

### Contextual permission onboarding (`RA_PermissionService`)

- **Cold start:** Zero permission popups on launch.
- **First routine arming:** `RA_PermissionService.ensureCoreAlarmPermissions(context)` runs when creating, importing, duplicating, resuming, or recovering a routine — requesting `POST_NOTIFICATIONS` (once), `SCHEDULE_EXACT_ALARM` only on API 31–32 when denied, and on Android 14+ explaining lock-screen Full-Screen Alert access via a themed in-app dialog before opening OS settings.
- **Settings → Alarm Reliability:** Unrestricted Battery exemption (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`), Lock-Screen Full-Screen Alert, and Display Over Active Apps fallback (`SYSTEM_ALERT_WINDOW`) are exposed as 1-tap controls with live status indicators. `scheduleNext` never invokes `requestIgnoreBatteryOptimizations`.

### Play policy journey (1.0.0 → 1.1.0)

Historical audit: [`play-policy-audit.md`](play-policy-audit.md) (and copy under `docs/`).

Problems found in 1.0.0:

1. Only `USE_EXACT_ALARM` was declared, so Android 12 / 12L (API 31 / 32) could not schedule exact alarms at all.
2. Ringing FGS used `specialUse`, which is a higher review risk than the documented `systemExempted` type for exact alarm clock apps.

1.0.1 fixed both and hardened wake / boot behaviour. Full change log: [`release-1.0.1-changes.md`](release-1.0.1-changes.md).

1.1.0 further hardened policy compliance by dropping `READ_MEDIA_AUDIO` / storage permissions in favor of `RingtoneManager` + `ACTION_OPEN_DOCUMENT`, replacing cold-start permission bombing with contextual `RA_PermissionService` onboarding, adding `AlarmSqliteGate.kt` for silent-mute correctness, and presenting Google Play Billing–compliant disclosures on `PaywallPage`.

Foreground service type in use now: **`systemExempted`**.

---

## 13. Home screen widget

- Jetpack Glance widget + `home_widget` bridge
- Per instance routine selection via `WidgetConfigActivity`
- Free tier allows 1 configured home screen widget; `WidgetConfigActivity` reads synced `ra_is_pro_effective` / `ra_is_pro` prefs and bridges non-Pro users adding additional widgets directly to `PaywallPage` via `com.casellaweb.rolling_alarm/paywall`
- Dart writes keys such as `routine_{id}_name`, next alarm time, interval label, dismissals today
- Native refresh helpers keep the widget in sync when schedules change

---

## 14. Import, export, and PDF

### RA1 import / export

`RA_ExportService` produces and consumes strings of the form:

```
RA1:<base64 JSON>
```

Current export version is **10**. Import reseeds next trigger times with the same `initialTriggerTime` rules as create, then arms OS timers.

### PDF

`RA_PdfService.shareLogsPdf` builds a printable log history and opens the system share sheet. Used from the global logs page when entries exist.

No network APIs are involved; share is local / OS mediated only.

---

## 15. Settings

Persisted via `RA_SettingsService` + Riverpod AsyncNotifiers:

| Setting | Effect |
| --- | --- |
| Rolling Alarm Pro | View Pro / Early Supporter status, open `PaywallPage`, restore purchases, or manage Play subscription |
| Theme | Dark / Light |
| Alarm snooze/dismiss layout | Sliders vs buttons on ring page |
| Side button actions | Volume up/down → None / Snooze / Dismiss while ringing (`Pro`) |
| Swipe actions | Left / right swipe on routine cards |
| Card buttons | Bottom left / right quick actions on cards |
| Alarm Reliability | 1-tap live status & OEM settings for Unrestricted Battery, Full-Screen Alert, and Display Over Active Apps |
| Import / Export | RA1 routines (`Export` requires `Pro`; `Import` honors Free 2-routine cap) |
| About & Legal | Privacy Policy, Terms of Use, App Version (`1.1.0`) |

---

## 16. Conventions and naming

| Convention | Detail |
| --- | --- |
| Folders | Layer first: `pages`, `services`, `components`, `database` (not feature first) |
| Prefix | `RA_` on reusable widgets, services, helpers |
| Screens | `*Page` suffix |
| Services | `*Service` suffix (often static methods) |
| Drift models | `*Model` via `@DataClassName` |
| Columns | PascalCase (`Id`, `CreatedAt`, `Deleted`) with audit columns on every table |
| Enums | Often `*Enum` / `*TypeCode` |
| Barrel files | Prefer none; import concrete files |
| Styles | Static tokens in `styles.dart`, not only `Theme.of` |
| Error handling | Fail soft at plugin / isolate boundaries (`RA_tryAsync`, guarded catches) |
| Analyzer | Configured to tolerate PascalCase / `RA_` style naming |

Architectural lineage: habits_together style conventions, with Riverpod + Drift instead of GetX.

This app does **not** use `the-good-library`. It is a standalone Flutter Android product under the Casella Web publisher identity.

---

## 17. Build, run, and develop

### Prerequisites

- Flutter SDK compatible with Dart `^3.8.0`
- Android SDK / emulator or device
- For release: `android/key.properties` + upload keystore (local only)

### Everyday run

```bat
run.bat
```

Optional first argument selects an AVD name (`samsung`, `Modern_Phone`, `Old_Small_Phone`, `Tablet_Device`, `MyResizable`, or a custom AVD). Extra args are forwarded to `flutter run`.

Or directly:

```bat
flutter run
```

### Analyze

```bat
flutter analyze
```

Uses `analysis_options.yaml` (build and android output excluded).

### Drift codegen

After changing tables:

```bat
dart run build_runner build
```

### Release bundle

```bat
flutter build appbundle --release
```

Output: `build\app\outputs\bundle\release\app-release.aab`  
`android/app/build.gradle.kts` reads `versionCode` / `versionName` from `pubspec.yaml`'s `version: name+code`.

### Helper scripts

| Script | Purpose |
| --- | --- |
| `scripts/run_screenshot_flow.ps1` | Screenshot automation flow |
| `scripts/run_integration_tests.ps1` | Orchestrates integration / Patrol |
| `scripts/pull_screenshots.ps1` | Pull device screenshots |
| `scripts/capture_play_screenshots.sh` | Play Store screenshot capture |
| `scripts/record_permission_demos.sh` | Record Play Console permission demos |
| `scripts/adb_grant_exact_alarm.ps1` | Grant exact alarm for testing |
| `scripts/_gen_branding.py` | Branding asset helper |

---

## 18. Testing

| Suite | Location | Notes |
| --- | --- | --- |
| Unit & Widget | `test/services/*`, `test/database/*`, `test/pages/*`, `test/utils_test.dart`, model/component tests | Calculator, daily limit, weekdays, export, purchase/grandfathering/paywall, alarm mute/schedule, in-memory & v17→v18 migration DB, mocks |
| Integration | `integration_test/app_test.dart`, `alarm_cycle_test.dart`, screenshot tests | Device / emulator |
| Patrol | `integration_test/advanced_alarm_lifecycle_test.dart` | Exact alarm / FSI / snooze dismiss lifecycle |
| Helpers | `integration_test/helpers/*` | Pump + Android alarm helpers |

Example Patrol run:

```bat
patrol test -t integration_test/advanced_alarm_lifecycle_test.dart
```

`pubspec.yaml` Patrol block: app name "Rolling Alarm", package `com.casellaweb.rolling_alarm`.

---

## 19. Release and Google Play

- Package: `com.casellaweb.rolling_alarm`
- Signed with the Casella Web upload key (keystore not in git)
- Current release line: **1.1.0+5**
- Optional RevenueCat key for release builds: `--dart-define=REVENUECAT_ANDROID_API_KEY=...`
- Sensitive permission declarations for Play Console must match the current manifest:
  - Exact alarm: alarm clock core functionality (`USE_EXACT_ALARM`; `SCHEDULE_EXACT_ALARM` capped at API 32)
  - Full screen intent: alarm ring over lock screen
  - Foreground service: **system exempted** for ringing until dismiss/snooze

Demo videos at repo root for Play declarations:

- `exact_alarm_demo.mp4`
- `fullscreen_intent_demo.mp4`
- `foreground_service_demo.mp4`

Listing helpers under `#GooglePlay/`: `translations.csv` (10-locale ASO store listing) and `release-notes-1.1.0.xml` (10-locale Play Console release notes).

Privacy policy (`https://casellaweb.com.au/privacy/rolling-alarm`) and Terms of Use (`https://casellaweb.com.au/terms/rolling-alarm`) cover the offline-first zero-tracking posture and optional Google Play Billing upgrades via RevenueCat.

---

## 20. Alternate entry points and tooling

| Entry | Purpose |
| --- | --- |
| `lib/main.dart` | Production |
| `lib/main_screenshots.dart` | Wipe DB/prefs, seed demo data, open scenes for Play screenshots |
| `lib/main_permission_demo.dart` | Seed a soon due routine for permission demo recording (not shipped) |

These alternate mains are development / store tooling only.

---

## 21. Related documentation

| Document | Content |
| --- | --- |
| [`docs/features-and-alarm-time-logic.md`](docs/features-and-alarm-time-logic.md) | Authoritative feature inventory + every next fire case |
| [`docs/stitch-ui-blueprint.md`](docs/stitch-ui-blueprint.md) | Full UI/UX blueprint for redesign |
| [`docs/play-policy-audit.md`](docs/play-policy-audit.md) / [`play-policy-audit.md`](play-policy-audit.md) | Historical Play sensitive permission audit (pre 1.0.1) |
| [`release-1.0.1-changes.md`](release-1.0.1-changes.md) | Exact alarm + FGS `systemExempted` + reliability fixes |
| [`docs/logo-design-brief.md`](docs/logo-design-brief.md) | Branding brief |
| `rolling_alarm_foundation_*.plan.md` | Original scaffold / TDD plan |
| `screenshots/README.txt` | How to capture / pull QA screenshots |

---

## 22. Known follow ups

These remain tracked for future releases:

1. Confirm Git remote URL points at `https://github.com/MrJames12345/RollingAlarm.git` (repo was renamed from an earlier CarsonAlarm name).
2. Upgrade `home_widget` / `patrol` when they stop applying the Kotlin Gradle Plugin themselves, before a future Flutter release refuses those plugins.
3. Keep device testing coverage on Android 12 and Android 14+ with the screen locked after any further alarm stack changes.

---

## Quick mental model

Rolling Alarm stores the next fire in Drift, arms both a Dart isolate timer and a native `setAlarmClock`, wakes into a full screen ring via a `systemExempted` foreground service, then recomputes the next fire from interval math (plus optional daily caps and weekdays) every time the user dismisses, skips, snoozes, or is auto snoozed. Everything stays on device.
