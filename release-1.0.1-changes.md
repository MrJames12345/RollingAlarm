# Rolling Alarm 1.0.1 (build 4): Change Log

**Date:** 3 October 2026
**Branch:** `main`, pushed to `origin` (GitHub, now `MrJames12345/RollingAlarm`)
**Release bundle:** `C:\Users\jayms\OneDrive\Desktop\rolling_alarm_update.aab` (version code 4, version name 1.0.1, signed with the Casella Web upload key)

This document explains every change made for the 1.0.1 release: why each change was needed, exactly what was changed, how it was verified, and what remains to be done in Play Console. It follows the findings in `play-policy-audit.md`, which records the state of the app **before** these changes.

## Contents

1. [Background](#1-background)
2. [Manifest changes](#2-manifest-changes)
3. [Foreground service type in AlarmRingingService](#3-foreground-service-type-in-alarmringingservice)
4. [Reliability hardening](#4-reliability-hardening)
5. [Version bump](#5-version-bump)
6. [Release build and verification](#6-release-build-and-verification)
7. [Documentation added](#7-documentation-added)
8. [Other changes included in the commits](#8-other-changes-included-in-the-commits)
9. [Commit history](#9-commit-history)
10. [Play Console actions still required](#10-play-console-actions-still-required)
11. [Known follow ups](#11-known-follow-ups)

## 1. Background

The audit of the original 1.0.0 submission found one failing check and one significant review risk:

1. **Failing check:** the app only declared `USE_EXACT_ALARM`, which exists from API 33. With a minSdk of 24, devices on Android 12 and 12L (API 31 and 32) had no exact alarm permission at all, so `canScheduleExactAlarms()` always returned false and **no alarms fired on those devices**.
2. **Review risk:** the ringing service used the `specialUse` foreground service type. Play only allows `specialUse` when no other type fits, and Android's documentation names `systemExempted` as the type for apps holding an exact alarm permission that use a foreground service to keep an alarm ringing.

The audit also identified three reliability gaps (H1, H2, H3) that were not policy blockers but could cause missed or truncated alarms.

All of these were addressed, using **Option B** from the audit (switch to `systemExempted`).

## 2. Manifest changes

**File:** `android/app/src/main/AndroidManifest.xml`

### 2.1 Exact alarm permissions

**Before**

```xml
<uses-permission android:name="android.permission.USE_EXACT_ALARM" />
```

**After**

```xml
<uses-permission
    android:name="android.permission.SCHEDULE_EXACT_ALARM"
    android:maxSdkVersion="32" />
<uses-permission android:name="android.permission.USE_EXACT_ALARM" />
```

**Why**

* On **API 31 and 32**, `SCHEDULE_EXACT_ALARM` is granted automatically at install time. Declaring it means `canScheduleExactAlarms()` now returns true on Android 12 and 12L, so both the native `setAlarmClock` path and the `android_alarm_manager_plus` `setExactAndAllowWhileIdle` path arm successfully.
* `android:maxSdkVersion="32"` stops the permission being requested on API 33 and above. There, `USE_EXACT_ALARM` applies instead. It is granted at install and cannot be revoked by the user, so users never see the "Alarms and reminders" toggle.
* This pairing is the pattern Google documents for alarm clock apps.

**Effect on users:** alarms now work on Android 12 and 12L. Nothing changes for Android 13 and above. No new permission prompt is shown on any version.

### 2.2 Foreground service permission

**Before**

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
```

**After**

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SYSTEM_EXEMPTED" />
```

**Why:** from Android 14, each foreground service type needs its matching permission. Moving the service to `systemExempted` requires `FOREGROUND_SERVICE_SYSTEM_EXEMPTED`, and `FOREGROUND_SERVICE_SPECIAL_USE` is no longer used, so it was removed rather than left as an unused sensitive permission that Play would still ask about.

### 2.3 Service declaration

**Before**

```xml
<service
    android:name=".AlarmRingingService"
    android:exported="false"
    android:foregroundServiceType="specialUse">
    <property
        android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
        android:value="Exact alarm full-screen ringing UI" />
</service>
```

**After**

```xml
<service
    android:name=".AlarmRingingService"
    android:exported="false"
    android:foregroundServiceType="systemExempted" />
```

**Why**

* `systemExempted` is the documented type for an alarm app that keeps ringing in the background while holding `SCHEDULE_EXACT_ALARM` or `USE_EXACT_ALARM`, which is exactly what `AlarmRingingService` does.
* The `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` property only applies to `specialUse` services, so it was deleted.
* `systemExempted` is only honoured while the app holds an exact alarm permission. The change in 2.1 guarantees that on every supported version from API 31 upward.

## 3. Foreground service type in AlarmRingingService

**File:** `android/app/src/main/kotlin/com/casellaweb/rolling_alarm/AlarmRingingService.kt`

The type passed to `startForeground()` must match the type declared in the manifest, otherwise Android 14+ throws an exception when the service starts. Both call sites were updated:

1. The initial `startForeground()` in `onStartCommand`, which runs when the alarm fires.
2. The re-promotion in `demoteToQuietServiceNotification`, which swaps to a quiet notification when the user locks the phone mid-ring.

**Before**

```kotlin
startForeground(
    notificationId(routineId),
    notification,
    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
)
```

**After**

```kotlin
startForeground(
    notificationId(routineId),
    notification,
    ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED
)
```

Both calls stay inside the existing `Build.VERSION_CODES.UPSIDE_DOWN_CAKE` (API 34) check. `FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED` is an API 34 constant, so older devices keep using the untyped `startForeground(id, notification)` overload exactly as before.

## 4. Reliability hardening

### 4.1 H1: wake lock gap between the receiver and the service

**File:** `android/app/src/main/kotlin/com/casellaweb/rolling_alarm/AlarmReceiver.kt`

**The problem:** when the alarm fires, `AlarmReceiver` takes a 5 second partial wake lock, then calls `startForegroundService()`. It previously released that lock in a `finally` block straight away. But `startForegroundService()` is asynchronous: the service's `onStartCommand`, where it takes its own wake lock, only runs on the main thread after `onReceive` has returned. That left a window where nothing held the CPU awake, and a dozing device could stall before the alarm started ringing.

**Before**

```kotlin
try {
    AlarmRingingService.start(context, safeIntent)
} catch (e: Exception) {
    // Android 12+ ForegroundServiceStartNotAllowedException fallback
    AlarmRingingService.showFallbackNotification(context, safeIntent)
} finally {
    // FGS holds its own wake lock; release this bridge lock promptly.
    try {
        if (wakeLock.isHeld) {
            wakeLock.release()
        }
    } catch (_: Exception) {
    }
}
```

**After**

```kotlin
try {
    AlarmRingingService.start(context, safeIntent)
} catch (e: Exception) {
    // Android 12+ ForegroundServiceStartNotAllowedException fallback
    AlarmRingingService.showFallbackNotification(context, safeIntent)
}
// Bridge lock self-expires after WAKE_LOCK_TIMEOUT_MS so the CPU stays
// awake until AlarmRingingService.onStartCommand acquires its own lock.
```

**Why this is safe:** the lock is acquired with `acquire(WAKE_LOCK_TIMEOUT_MS)` (5 seconds) and is not reference counted, so it always releases itself. The early return path for an invalid routine id still releases it immediately, because no service is started in that case.

### 4.2 H2: ringing wake lock capped too short

**File:** `android/app/src/main/kotlin/com/casellaweb/rolling_alarm/AlarmRingingService.kt`

**The problem:** the service's partial wake lock was capped at 2 minutes. It is re-acquired once when the bright screen lock is downgraded after 4 seconds, so CPU coverage ended at roughly 2 minutes 4 seconds even if the alarm was still ringing. The audio server keeps sound playing on its own lock, but work on the service's main thread (the fade in, the screen off handling, and the wake fallback timers) could stall once the device dozed.

**Before**

```kotlin
/** Cap PARTIAL wake while ringing; service stops on dismiss/snooze. */
private const val MAX_WAKE_LOCK_MS = 2 * 60_000L
```

**After**

```kotlin
/** Cap PARTIAL wake while ringing; service stops on dismiss/snooze. */
private const val MAX_WAKE_LOCK_MS = 10 * 60_000L
```

**Why this is safe for battery:** the cap is only a safety net. The lock is still released in `onDestroy` as soon as the user dismisses or snoozes, so in normal use it is held for exactly as long as the alarm rings.

### 4.3 H3: boot receiver deleting alarms

**File:** `android/app/src/main/kotlin/com/casellaweb/rolling_alarm/AlarmResurrectionReceiver.kt`

**The problem:** after a reboot or app update, `rescheduleAlarms` walks the saved alarms and re-arms each one. If arming threw an exception, for example because exact alarm access was unavailable, the per-entry `catch` removed the saved entry. Every pending alarm could be permanently erased in a single boot.

**Change:** a guard at the top of `rescheduleAlarms` returns early, leaving every saved entry untouched, when exact alarms cannot be scheduled. The next app launch reconciles and re-arms them.

```kotlin
import android.app.AlarmManager
import android.os.Build

private fun rescheduleAlarms(context: Context) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        // Keep saved entries so the next app launch can re-arm them.
        if (!am.canScheduleExactAlarms()) return
    }
    // ... existing body unchanged ...
}
```

The two new imports were added to the top of the file. The rest of the method, including the removal of alarms whose time has already passed, is unchanged.

## 5. Version bump

**File:** `pubspec.yaml`

```yaml
version: 1.0.1+4
```

Previously `1.0.0+1`. Play requires every upload to have a version code that has never been used before. `android/app/build.gradle.kts` reads `versionCode = flutter.versionCode` and `versionName = flutter.versionName`, so this single line sets both: **version code 4** and **version name 1.0.1**.

The first 1.0.1 build used `1.0.1+2`, but Play Console rejected it with "Version code 2 has already been used", because an earlier upload had already taken that code. The build number was raised to 3, and then to 4 for a later rebuild that also picked up the alarm audio rework, since any unused code is accepted.

## 6. Release build and verification

### 6.1 Build

```powershell
flutter build appbundle --release
```

The build succeeded in about 2.5 minutes and produced `build\app\outputs\bundle\release\app-release.aab` (64.9 MB).

The build printed one warning: the `home_widget` and `patrol` plugins still apply the Kotlin Gradle Plugin themselves, and a future Flutter version will refuse to build with plugins like that. It does not affect this build. See [Known follow ups](#11-known-follow-ups).

### 6.2 Verification of the built artifact

Each check below was run against the freshly built output, not the source files:

| Check | Result |
|---|---|
| Merged release manifest `versionCode` | `4` |
| Merged release manifest `versionName` | `1.0.1` |
| `SCHEDULE_EXACT_ALARM` present with `maxSdkVersion="32"` | Yes |
| `USE_EXACT_ALARM` present | Yes |
| `FOREGROUND_SERVICE_SYSTEM_EXEMPTED` present | Yes |
| Any remaining `specialUse` or `FOREGROUND_SERVICE_SPECIAL_USE` | None |
| `AlarmRingingService` type | `systemExempted` |
| Bundle signature (`jarsigner -verify`) | Verified, signed by `CN=Casella Web, OU=Development, O=Casella Web, L=Perth, ST=Western Australia, C=AU` |

### 6.3 Export

The bundle was copied to the Desktop as `rolling_alarm_update.aab`. The Desktop on this machine is redirected to OneDrive, so the real path is `C:\Users\jayms\OneDrive\Desktop\rolling_alarm_update.aab`. The suggested `$env:USERPROFILE\Desktop` path would have written to a folder that Explorer does not show as the Desktop, so the copy used `[Environment]::GetFolderPath('Desktop')` instead.

### 6.4 What was not verified

The build has not been installed and run on a device. The `systemExempted` ring path has been checked by compilation and manifest inspection only. Before uploading, it is worth installing the release build on an Android 14 or newer device and on an Android 12 device, then confirming an alarm fires while the screen is locked.

## 7. Documentation added

| File | Purpose |
|---|---|
| `play-policy-audit.md` | Full audit of the 1.0.0 submission against Android 14+ and Play policy requirements for the three sensitive permissions. |
| `docs/play-policy-audit.md` | Identical copy kept with the other project docs. |
| `release-1.0.1-changes.md` | This file. |

The audit describes the app **before** these fixes, so it still presents `specialUse` as the current setup. Treat it as the historical record that motivated this release.

## 8. Other changes included in the commits

When the work was committed, the working tree also contained changes made earlier, outside this set of fixes. They were reviewed, grouped and committed alongside the policy work, but their content was not authored as part of it:

1. **`file_picker` upgrade to 13.1.** `pubspec.yaml` previously pinned `file_picker: 10.3.10` with a comment explaining that 11.x failed Android builds under AGP 9. It is now `^13.1.0`, `android/gradle.properties` switches `android.builtInKotlin` to `true`, and `lib/services/alarm_sound_picker.dart` moved from `FilePicker.platform.pickFiles` to the single file `FilePicker.pickFile` API, using `file.uri` as the fallback when there is no file path. That file was also reformatted by `dart format`. `pubspec.lock` carries the resulting dependency updates.
2. **Analyzer configuration.** `analysis_options.yaml` now excludes `build/**` and `android/**` from Dart analysis, and a stray byte order mark at the start of the file was removed.
3. **Screenshot script fix.** In `scripts/capture_play_screenshots.sh`, the ready check piped `adb logcat` into `grep -q`. Under `set -o pipefail`, `grep` exiting early on a match made the still-writing `adb` side report failure, so a successful match could be read as a failure. The logcat output is now captured into a variable first and matched with a shell pattern.
4. **Permission demo tooling.** `lib/main_permission_demo.dart` is a separate entry point, never shipped, that seeds a routine due a few seconds after launch. `scripts/record_permission_demos.sh` builds it and records the three Play Console demonstration videos automatically.
5. **Demo videos.** `exact_alarm_demo.mp4`, `fullscreen_intent_demo.mp4` and `foreground_service_demo.mp4` (about 16.5 MB in total) at the project root.

Files deliberately **not** committed: `android/key.properties` and `android/app/upload-keystore.jks` are gitignored, as is everything under `build/`.

## 9. Commit history

All commits are authored and committed by **James Casella `<james@casellaweb.com.au>`** and were pushed to `origin/main` (`e509ceb..2047b30`).

| Commit | Message |
|---|---|
| `1181078` | Upgrade file_picker to 13.1 with built-in Kotlin and move the local sound picker to the single file API. |
| `6c639b7` | Exclude build and Android output from the Dart analyzer and drop the BOM from analysis_options.yaml. |
| `2b0702c` | Fix the screenshot ready check failing under pipefail when grep exits before adb. |
| `31ca403` | Run the alarm ringing service as systemExempted and declare SCHEDULE_EXACT_ALARM for Android 12 and 12L. |
| `f252972` | Keep the CPU awake through the whole alarm ring and stop boot rescheduling from deleting alarms without exact alarm access. |
| `c807b60` | Add the Google Play sensitive permission audit for exact alarms, full screen intents and the ringing service. |
| `cb26149` | Add a scripted recorder for the Play Console permission demo videos with a seeded demo entry point. |
| `d44e850` | Add the exact alarm, full screen intent and foreground service demo videos for the Play Console declarations. |
| `2047b30` | Bump version to 1.0.1+2. |

The later bumps to `1.0.1+3` and `1.0.1+4`, made after Play Console rejected version code 2, are not yet committed.

`pubspec.yaml` and `AlarmRingingService.kt` each contained changes belonging to two different groups. They were staged in parts, so the dependency commit does not include the version bump, and the service type commit does not include the wake lock change.

## 10. Play Console actions still required

The new bundle no longer matches the declarations made for 1.0.0. Update these before or while uploading 1.0.1:

1. **Foreground service permissions:** change the declaration from **special use** to **system exempted**, describing the use as ringing a user-scheduled alarm clock alarm until the user dismisses or snoozes it. The existing `foreground_service_demo.mp4` still shows the correct behaviour and can be reused.
2. **Exact alarm permission:** declare `USE_EXACT_ALARM` with **alarm clock** as the core functionality. `SCHEDULE_EXACT_ALARM` is now capped at API 32 and does not need its own declaration.
3. **Full-screen intent:** no change. The declaration and `fullscreen_intent_demo.mp4` remain valid.
4. **Upload** `rolling_alarm_update.aab` to a new release and resubmit for review.

## 11. Known follow ups

1. **Git remote has moved.** GitHub reports the repository moved from `CarsonAlarm` to `RollingAlarm`. Pushes still work through the redirect, but the remote should be updated:

   ```powershell
   git remote set-url origin https://github.com/MrJames12345/RollingAlarm.git
   ```

2. **Stale label in the demo script.** The header of `scripts/record_permission_demos.sh` still describes `foreground_service_demo.mp4` as `FOREGROUND_SERVICE_SPECIAL_USE`. It should read `FOREGROUND_SERVICE_SYSTEM_EXEMPTED`.
3. **Plugins applying the Kotlin Gradle Plugin.** `home_widget` and `patrol` need upgrading to versions that support Flutter's built-in Kotlin before a future Flutter release stops building them.
4. **Device testing.** Run the release build on Android 12 and Android 14+ devices to confirm alarms fire on time with the screen locked, as noted in [section 6.4](#64-what-was-not-verified).
