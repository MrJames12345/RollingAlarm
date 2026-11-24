# Rolling Alarm — Google Play Custom Store Listings (v1.1.0)

Ready-to-paste `en-US` / `en-AU` copy for Google Play Console -> **Grow users -> Store listings -> Custom store listings**.
Each listing matches the exact `?listing=` URL slug routed from `https://casellaweb.com.au/rolling-alarm?for=<meds|fifo|adhd>` and includes an **Ask Play Quick Specs** capability block at the very top of the Full Description for Google Play AI comparison cards.

> **Play Console Character Limits Verified:** Title `<= 30` chars (contains `"Alarm"`), Short Description `<= 80` chars, Full Description `<= 4000` chars, zero `"no paywalls"` phrasing.

| # | Custom URL Slug (`?listing=`) | Web Router Source | Title (`<= 30`) | Short Desc (`<= 80`) |
| --- | --- | --- | --- | --- |
| 1 | `medication-reminder` | `?for=meds` | `Rolling Alarm: Pill Med Alarm` (29) | 76 chars |
| 2 | `shift-fifo-alarm` | `?for=fifo` | `Rolling Alarm: Shift & FIFO` (27) | 77 chars |
| 3 | `adhd-routine-timer` | `?for=adhd` | `Rolling Alarm: Routine Alarm` (28) | 79 chars |

*(Note: `"Rolling Alarm: Pill & Med Alarm"` is 31 chars, 1 char over Google Play's hard 30-char cap, so Listing 1 uses `Rolling Alarm: Pill Med Alarm` [29 chars] to retain all high-intent keywords cleanly.)*

---

## Listing 1 — Medication & Post-Op Dose Spacing (`listing=medication-reminder`)

- **Custom URL:** `https://play.google.com/store/apps/details?id=com.casellaweb.rolling_alarm&listing=medication-reminder`
- **Target Audience:** Displaced *Medisafe* users, post-surgery recovery patients, chronic dose-interval schedules (4h / 6h / 8h), and family caregivers seeking a 100% offline, account-free alternative to subscription pill-tracker apps.

### App Name / Title (`29 / 30` chars)
```text
Rolling Alarm: Pill Med Alarm
```

### Short Description (`76 / 80` chars)
```text
Offline pill & dose interval alarm. Next dose rolls from dismissal. No subs!
```

### Full Description (`<= 4000` chars)
```text
Quick Specs & Capabilities:
• Core Function: True post-dismissal medication interval alarm (Next Dose = Actual Taken Time + 4h/6h/8h) with full-screen lock-screen wake.
• Built For: Post-surgery pain relief spacing, multi-dose antibiotics, eye drops, chronic pill cadences, and caregiver adherence tracking.
• Offline & Privacy: 100% offline on-device SQLite storage. Zero health accounts, zero cloud sync, zero ads, and zero personal data collection.
• Free vs. Pro: Free forever for up to 2 live medication routines, daily dose caps, overnight Day-Start parking, 1 home widget, and 7-day logs; optional Rolling Alarm Pro (one-time Lifetime unlock, Annual, or Monthly) adds unlimited medications, 365-day logs, and printable doctor PDF adherence reports.

Stop fighting fixed clock alarms—or paying recurring monthly subscriptions just to remember your next pill. Rolling Alarm is a calm, 100% offline medication dose interval alarm built around when you actually took your last dose.

Why fixed clock alarms fail for medication spacing:
If you sleep in or take your morning dose 45 minutes late, fixed 8:00 AM / 12:00 PM / 4:00 PM alarms collide and risk overlapping doses. Rolling Alarm works on a true continuous rolling loop: the exact moment you dismiss an alarm after taking your dose, your next reminder is automatically scheduled 4, 6, or 8 hours from right then.

Built for stress-free medical adherence:
• True Post-Dismissal Dose Spacing: Took your 6-hour dose at 8:42 AM? Your next alarm automatically rolls to 2:42 PM—zero manual mental math.
• Daily Dose Caps & Overnight Day-Start Parking: Cap a course at 3 or 4 doses per day and set your Day Start Time (e.g. 7:00 AM) so overnight doses park cleanly until morning without waking the house at 3:00 AM.
• Full-Screen Lock-Screen Wake: Unlike silent notification banners that vanish in your shade, Rolling Alarm wakes over your lock screen with tactile dismiss & snooze sliders.
• Printable Doctor & Caregiver PDF Reports: Export clean, timestamped adherence logs (dismissals, snoozes, skips, and muted cycles) as printable PDFs for GP visits, specialists, or hospital handovers.
• 1-Tap Caregiver Routine Sharing: Set up a relative's dosing cadence once and share it freely via an offline RA1: preset link.
• 100% Private Medical Data: Your medication names and dosing logs stay strictly inside on-device SQLite storage. No account creation, no cloud servers, no pharma ad networks, and no tracking.
• OEM Battery Reliability Guide: Built-in setup assistant ensures alarms fire reliably on Samsung, Xiaomi, Oppo, and Vivo devices.

Own your pill alarm outright:
Core medication routines are free forever (up to 2 live routines, daily caps, Day-Start parking, 1 home widget, and 7-day logs). Need unlimited routines, custom fade-in sounds, 365-day history, and printable PDF reports? Upgrade optionally to Rolling Alarm Pro—including a single one-time Lifetime purchase with no ongoing subscription required.
```

---

## Listing 2 — WA FIFO & Rotating Nursing Shift Rosters (`listing=shift-fifo-alarm`)

- **Custom URL:** `https://play.google.com/store/apps/details?id=com.casellaweb.rolling_alarm&listing=shift-fifo-alarm`
- **Target Audience:** Western Australian FIFO workers (`8/6`, `2/1`, `2/2` swings), hospital nurses (`4-on-4-off`, rotating 12h days/nights), paramedics, and remote site crews working in zero-reception camps.

### App Name / Title (`27 / 30` chars)
```text
Rolling Alarm: Shift & FIFO
```

### Short Description (`77 / 80` chars)
```text
WA FIFO 8/6, 2/1 & nursing 4-on-4-off swing alarm. Auto R&R parking, offline.
```

### Full Description (`<= 4000` chars)
```text
Quick Specs & Capabilities:
• Core Function: Automatic N-days-ON / M-days-OFF swing-roster & turnaround interval alarm with full-screen lock-screen wake.
• Built For: WA FIFO rosters (8/6, 2/1, 2/2), rotating hospital nursing (4-on-4-off), 12-hour shift turnarounds, and remote zero-reception camps.
• Offline & Privacy: 100% offline on-device SQLite & native Android AlarmManager. Zero signal required, zero accounts, zero ads, and zero tracking.
• Free vs. Pro: Free forever for up to 2 live routines, 8/6 & 4-on-4-off swing presets, 1 home widget, 7-day logs, and free RA1: crew sharing; optional Rolling Alarm Pro (one-time Lifetime unlock, Annual, or Monthly) adds unlimited rosters, 2/1 (14/7) & 2/2 (14/14) custom cycles, custom local audio/fade-in, hardware volume controls, and 365-day logs.

Never get jolted awake at 4:30 AM on your first day of R&R again—and never forget to re-enable your site alarm before fly-in day. Rolling Alarm automates FIFO and nursing swing-roster cycles with rock-solid offline Android reliability.

Purpose-built for FIFO swings & rotating 12-hour rosters:
• Automatic Swing-Roster Engine: Configure 8/6, 2/1 (14/7), 2/2 (14/14), 4-on-4-off, or any custom N-days-ON / M-days-OFF roster anchored to Day 1 of your current swing.
• Automatic R&R Off-Swing Parking: The moment your final shift finishes, Rolling Alarm parks silently across your entire R&R block (enforced natively inside Android's Kotlin alarm service) and wakes cleanly at your Day Start Time on fly-in morning.
• 12-Hour Turnaround Rolling Loops: On night-shift or rolling turnarounds, your next alarm rolls directly from dismissal so delayed crib breaks or late handovers stay locked to your real sleep window.
• Built for Zero-Reception Camps & Dongas: 100% offline SQLite scheduling with zero cloud dependency—works identically in airplane mode at Pilbara, Goldfields, or offshore sites.
• 1-Tap Crew Roster Sharing: Built your exact site swing? Tap Share Routine Preset to send a free RA1: link to your crewmates so they import the entire roster in seconds.
• Live Dashboard & Home Screen Widget: See your exact swing status at a glance (e.g. "8/6 Swing · Day 3 of 8 ON" or "R&R Off-Swing · Starts Tue 5:00 AM").
• OEM Battery Reliability Guide: Guided battery-exemption checks for Samsung, Xiaomi, Oppo, and Vivo handsets so aggressive OEM task killers never silence your pre-start alarm.

Fair, straightforward pricing:
Free forever for up to 2 live routines, built-in 8/6 FIFO and 4-on-4-off nursing templates, 1 home screen widget, and free RA1: sharing. Upgrade optionally to Rolling Alarm Pro—with a one-time Lifetime unlock as well as annual and monthly plans—for unlimited rosters, 2/1 & 2/2 custom swing cycles, custom wake audio, gentle fade-in, and 365-day logs.
```

---

## Listing 3 — ADHD Time-Blindness & Routine Loops (`listing=adhd-routine-timer`)

- **Custom URL:** `https://play.google.com/store/apps/details?id=com.casellaweb.rolling_alarm&listing=adhd-routine-timer`
- **Target Audience:** Adults and students managing ADHD time blindness, hyperfocus breaks, hydration/posture resets, and task transitions who swipe away silent notifications without noticing them.

### App Name / Title (`28 / 30` chars)
```text
Rolling Alarm: Routine Alarm
```

### Short Description (`79 / 80` chars)
```text
ADHD time-blindness interval alarm. Full-screen wake loops & countdown widgets.
```

### Full Description (`<= 4000` chars)
```text
Quick Specs & Capabilities:
• Core Function: Persistent full-screen interval loop alarm (Actual Dismissal or Classic Interval drift-absorbing grid) with live home-screen countdown widgets.
• Built For: ADHD time blindness, 90-minute focus & hydration grids, hyperfocus task transitions, posture resets, and daily executive-function anchors.
• Offline & Privacy: 100% offline on-device SQLite storage. Zero accounts, zero social noise, zero ads, and zero tracking.
• Free vs. Pro: Free forever for up to 2 live routines, 1 home-screen countdown widget, 1-tap quick-start templates, and 7-day logs; optional Rolling Alarm Pro (one-time Lifetime unlock, Annual, or Monthly) adds unlimited routines & widgets, Classic Interval drift-absorbing grids, custom local audio/fade-in, and 365-day logs.

Silent notification banners don't break hyperfocus—you swipe them away on autopilot and lose two hours. Rolling Alarm replaces forgettable pings with calm, unmistakable full-screen interval cues built for brains that lose track of time.

Designed around how ADHD routines actually work:
• Full-Screen Cues You Can't Accidentally Swipe Away: Every interval brings up a crisp, distraction-free full-screen wake view with dedicated dismiss and snooze sliders so you consciously register the transition.
• Two Drift Modes for Real Life: Choose Actual Dismissal (next loop rolls cleanly from when you actually stop hyperfocusing) or Classic Interval (absorbs snooze time to hold a steady 90-minute focus & hydration grid across your workday).
• Glanceable Home Screen Countdown Widgets: Keep time visible outside your head with live home-screen cards showing exact remaining countdowns and daily ring progress.
• Zero Setup Paralysis: Launch the built-in ADHD Focus / Hydration Grid template in one tap, or pause any routine mid-loop with frozen remaining time whenever meetings or errands interrupt.
• Quiet Hours & Weekday Rules: Automatically cap daily rings (e.g. 8/day Mon–Fri) and park evenings cleanly until tomorrow's Day Start Time so work cues stay off during rest.
• Calm, Zero-Distraction Interface: High-contrast dark chronometer design with zero ads, zero streaks nagging you with guilt, zero pop-up banners, and zero account walls.
• 1-Tap Routine Sharing: Share proven executive-function templates with friends, coaches, or study partners freely via RA1: preset links.

Fair, one-time friendly pricing:
Start free forever with up to 2 live routines, 1 live home widget, daily caps, weekday rules, and 7-day history. Upgrade optionally to Rolling Alarm Pro—including a one-time Lifetime unlock alongside annual and monthly plans—for unlimited routines and widgets, Classic Interval drift compensation, gentle fade-in audio, and full 365-day logs.
```
