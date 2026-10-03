# Google Play Policy Audit: Sensitive Permissions

**App:** Rolling Alarm (`com.casellaweb.rolling_alarm`)
**Audit date:** 3 October 2026
**Scope:** `FOREGROUND_SERVICE_SPECIAL_USE`, `USE_FULL_SCREEN_INTENT`, `SCHEDULE_EXACT_ALARM` against Android 14+ requirements and Google Play policy.
**Build inspected:** merged release manifest at `build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml` (targetSdk 36, minSdk 24), plus all Kotlin sources under `android/app/src/main/kotlin/com/casellaweb/rolling_alarm/` and the Dart alarm services.

## Verdict

**FAIL** as submitted.

One required check fails: `SCHEDULE_EXACT_ALARM` is not declared anywhere in the app. This is a genuine functional bug on Android 12 and 12L, and it also creates a mismatch between the permissions declared in Play Console and the permissions in the uploaded bundle.

Everything else (foreground service type, special use subtype property, `startForeground()` timing, wake lock handling, full-screen intent wiring, exact alarm APIs and the `canScheduleExactAlarms()` guard) passes.

After applying the single required fix in [Required fix](#required-fix) and aligning the Play Console declaration, the app is rated **PASS**. The items under [Recommended hardening](#recommended-hardening) improve alarm reliability but are not policy blockers. The [specialUse review risk](#review-risk-specialuse-versus-systemexempted) section describes the most likely reason a strict reviewer could still push back.

## Summary of checks

| # | Check | Result |
|---|---|---|
| 1.1 | `FOREGROUND_SERVICE_SPECIAL_USE` declared | Pass |
| 1.2 | `USE_FULL_SCREEN_INTENT` declared | Pass |
| 1.3 | `SCHEDULE_EXACT_ALARM` declared | **Fail** |
| 1.4 | Service declares `android:foregroundServiceType="specialUse"` | Pass |
| 1.5 | `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` defined inside the service tag | Pass |
| 2.1 | `startForeground()` called promptly with a valid notification and type | Pass |
| 2.2 | Wake lock acquired while ringing and released on stop | Pass, with two reliability gaps |
| 3.1 | `setFullScreenIntent()` used and targets the ringing UI | Pass |
| 4.1 | Exact alarm API used to trigger the alarm | Pass |
| 4.2 | `canScheduleExactAlarms()` checked on API 31+ with graceful handling | Pass in code, but always false on API 31 and 32 because of 1.3 |

## 1. Manifest declarations

### 1.1 and 1.2: FGS special use and full-screen intent permissions (Pass)

Both are declared in `android/app/src/main/AndroidManifest.xml` and survive into the merged release manifest:

```xml
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
```

### 1.3: SCHEDULE_EXACT_ALARM (Fail)

The only exact alarm permission in the app is:

```xml
<!-- Dedicated alarm/clock app: exact alarms without Android 14+ settings redirect. -->
<uses-permission android:name="android.permission.USE_EXACT_ALARM" />
```

No plugin merges `SCHEDULE_EXACT_ALARM` in either. The merged release manifest was checked directly and the permission is absent.

**Why this matters**

`USE_EXACT_ALARM` was introduced in API 33. The app's minSdk is 24, so it installs on API 31 and 32 (Android 12 and 12L), where `USE_EXACT_ALARM` does not exist. On those devices the app holds no exact alarm permission at all, which causes the following chain:

1. `AlarmManager.canScheduleExactAlarms()` always returns false.
2. `AlarmUiSchedulerPlugin` returns the `exact_alarm_denied` error and never calls `setAlarmClock`, so the native ring path (receiver, foreground service, full-screen intent) is never armed.
3. `android_alarm_manager_plus` 5.1.1 performs the same check internally (`AlarmService.java`, lines 169 to 171), logs `Can't schedule exact alarm due to revoked SCHEDULE_EXACT_ALARM permission`, and silently skips `setExactAndAllowWhileIdle`.
4. `Permission.scheduleExactAlarm.request()` in `lib/main.dart` opens the system "Alarms and reminders" page, but the app is not listed there because it never declared the permission, so the user cannot grant it.

Result: **no alarms fire on Android 12 or 12L.**

**Policy impact**

You stated that `SCHEDULE_EXACT_ALARM` was declared in Play Console, but the bundle only contains `USE_EXACT_ALARM`. Play reviews the permissions in the uploaded artifact, so the declaration and the binary should match. `USE_EXACT_ALARM` is the restricted permission that Play gates behind a declaration, and it is only allowed for apps whose core function is an alarm clock or calendar. Rolling Alarm qualifies, but the declaration must be the `USE_EXACT_ALARM` one.

See [Required fix](#required-fix) for the code change.

### 1.4: Foreground service type (Pass)

```xml
<service
    android:name=".AlarmRingingService"
    android:exported="false"
    android:foregroundServiceType="specialUse">
```

### 1.5: Special use subtype property (Pass)

The property is correctly nested inside the service tag, as Android 14 requires:

```xml
    <property
        android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
        android:value="Exact alarm full-screen ringing UI" />
</service>
```

The value is technically valid but thin. See [Review risk](#review-risk-specialuse-versus-systemexempted) for a stronger wording.

## 2. Service implementation

### 2.1: startForeground() timing and type (Pass)

In `AlarmRingingService.onStartCommand`, `startForeground()` is called right after the notification channel is created and the notification is built, before any audio, vibration or activity work. On API 34+ it passes the matching service type:

```kotlin
val notification = buildServiceNotification(this, routineId, useFsi = useFsi)
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
    startForeground(
        notificationId(routineId),
        notification,
        ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
    )
} else {
    startForeground(notificationId(routineId), notification)
}
```

Supporting details that also pass:

* The notification sets `setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)`, so it is shown without the default 10 second deferral.
* The service is started from the `AlarmManager.setAlarmClock` broadcast. Alarm clock broadcasts are exempt from the Android 12+ restriction on starting foreground services from the background.
* `AlarmReceiver` catches the start failure (for example `ForegroundServiceStartNotAllowedException`) and falls back to posting the full-screen notification directly.
* `demoteToQuietServiceNotification` also re-calls `startForeground()` with the correct type when the notification is swapped mid-ring.

### 2.2: Wake lock handling (Pass, with gaps)

`AlarmRingingService` declares `WAKE_LOCK`, acquires a lock in `onStartCommand`, downgrades it from a screen-bright wakeup lock to a `PARTIAL_WAKE_LOCK` after 4 seconds, and releases it in `onDestroy`:

```kotlin
override fun onDestroy() {
    unregisterScreenOffReceiver()
    AlarmRingtonePlayer.stop()
    try { AlarmVibrator.stop(this) } catch (_: Exception) {}
    cancelWakeFallback()
    cancelBrightWakeDowngrade()
    releaseWakeLock()
    ...
}
```

The lock is non reference counted, acquired with a timeout and released defensively, which satisfies the requirement. Two reliability gaps exist and are covered in [Recommended hardening](#recommended-hardening):

1. `AlarmReceiver` releases its bridge wake lock before the service has acquired its own.
2. The ringing lock is capped at about 2 minutes, which is shorter than an alarm can ring.

## 3. Full-screen intent

### 3.1: setFullScreenIntent() usage (Pass)

`AlarmRingingService.buildServiceNotification` attaches the full-screen intent whenever the device is locked, asleep, or another app is in the foreground:

```kotlin
if (useFsi) {
    val fullScreenPi = PendingIntent.getActivity(
        context,
        REQUEST_FSI_BASE + routineId,
        launchIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    builder
        .setCategory(NotificationCompat.CATEGORY_ALARM)
        .setPriority(NotificationCompat.PRIORITY_MAX)
        .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        .setFullScreenIntent(fullScreenPi, true)
}
```

What passes:

* **Target:** the PendingIntent opens `MainActivity` with `EXTRA_ALARM_RINGING` and the routine id. `MainActivity` calls `setShowWhenLocked(true)` and `setTurnScreenOn(true)` for that intent, and Flutter routes it to the ring page (`lib/pages/alarm_ring.dart`).
* **Channel:** posted on `ra_native_alarm_wake_v4`, which is `IMPORTANCE_HIGH` with `VISIBILITY_PUBLIC`, as full-screen intents require.
* **Category:** `CATEGORY_ALARM`, which matches the Play policy use case for full-screen intents.
* **Android 14 revocation handling:** `canUseFullScreenIntent()` calls `NotificationManager.canUseFullScreenIntent()` on API 34+. If the user or Play has revoked the permission, the service launches the ring activity directly instead of relying on a notification that would only show as a heads-up.
* **User prompt:** `RA_NotificationService.requestFullScreenIntentPermission()` is called at startup to send the user to Settings when the app op is not granted.

## 4. Exact alarms

### 4.1: Exact alarm API (Pass)

Two schedulers are used:

1. **Native (primary ring path):** `AlarmUiSchedulerPlugin.schedule` uses `AlarmManager.setAlarmClock(AlarmClockInfo, operation)`. This is stricter than `setExactAndAllowWhileIdle`. It is exact, Doze exempt, and shows the upcoming alarm in the status bar, and it is the API Google recommends for user-facing alarm clocks.
2. **Dart (state bookkeeping):** `RA_AlarmService.scheduleNext` calls `AndroidAlarmManager.oneShotAt` with `exact: true, wakeup: true, allowWhileIdle: true`. In `android_alarm_manager_plus` 5.1.1 this resolves to `AlarmManagerCompat.setExactAndAllowWhileIdle`.

### 4.2: canScheduleExactAlarms() guard (Pass in code, broken on API 31 and 32)

The native scheduler checks before arming and returns a localized error instead of throwing:

```kotlin
if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    if (!alarmManager.canScheduleExactAlarms()) {
        result.error("exact_alarm_denied", context.getString(R.string.error_exact_alarm_denied), null)
        return
    }
}
```

`android_alarm_manager_plus` performs the same check internally. The Dart caller wraps both calls in `try`/`catch`, so a denial never crashes the app.

The guard itself is correct. The problem is that on API 31 and 32 it always takes the denied branch, because of the missing manifest declaration described in 1.3.

On API 33+, `USE_EXACT_ALARM` is granted at install and cannot be revoked by the user, so `canScheduleExactAlarms()` always returns true there.

## Required fix

In `android/app/src/main/AndroidManifest.xml`, replace the existing `USE_EXACT_ALARM` line with this pair. It is the pattern Google documents for alarm clock apps:

```xml
<!-- API 31 and 32 only; USE_EXACT_ALARM covers API 33+. -->
<uses-permission
    android:name="android.permission.SCHEDULE_EXACT_ALARM"
    android:maxSdkVersion="32" />
<uses-permission android:name="android.permission.USE_EXACT_ALARM" />
```

Effect:

* **API 31 and 32:** `SCHEDULE_EXACT_ALARM` is granted automatically at install. `canScheduleExactAlarms()` returns true and alarms fire. No new runtime prompt is needed.
* **API 33+:** behaviour is unchanged. `USE_EXACT_ALARM` applies, and `SCHEDULE_EXACT_ALARM` is not requested, so the user never sees the "Alarms and reminders" toggle.

### Play Console actions

1. In **App content, Exact alarm permission**, declare `USE_EXACT_ALARM` and select **alarm clock** as the core functionality.
2. Make sure the store listing, short description and screenshots clearly present Rolling Alarm as an alarm clock. Reviewers reject `USE_EXACT_ALARM` when alarm functionality is not obviously the core purpose.
3. Upload a new bundle containing the manifest fix, then resubmit.

## Recommended hardening

These are not policy blockers, but each one closes a gap that can cause a missed or truncated alarm.

### H1: Wake lock gap between the receiver and the service

`AlarmReceiver` releases its bridge lock in `finally` immediately after `startForegroundService()`. The service's `onStartCommand` runs on the main thread only after `onReceive` returns, so between the release and the service acquiring its own lock, nothing holds the CPU awake. The lock already has a 5 second timeout, so it should simply be allowed to expire.

Replace the `try`/`catch`/`finally` block in `AlarmReceiver.onReceive` with:

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

### H2: Ringing wake lock lapses after about 2 minutes

`MAX_WAKE_LOCK_MS` in `AlarmRingingService` is 2 minutes. The partial lock is re-acquired once at the 4 second downgrade, so CPU coverage ends at roughly 2 minutes 4 seconds even if the alarm is still ringing. The audio server keeps sound playing on its own lock, but main thread work such as the fade-in, the screen-off handling and the wake fallback timers can stall once the device dozes.

```kotlin
/** Cap PARTIAL wake while ringing; service stops on dismiss/snooze. */
private const val MAX_WAKE_LOCK_MS = 10 * 60_000L
```

The lock is still released in `onDestroy` on dismiss or snooze, so a longer cap does not cost battery in normal use.

### H3: Boot receiver deletes alarms it fails to re-arm

In `AlarmResurrectionReceiver.rescheduleAlarms`, any exception thrown by `AlarmUiSchedulerPlugin.schedule` hits the per-entry `catch`, which removes the saved alarm. If exact alarm access is unavailable at boot, every pending alarm is permanently erased. Guard the whole method so entries survive until the app can re-arm them:

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

## Review risk: specialUse versus systemExempted

This is the most likely remaining reason for a rejection, even after the required fix.

Google Play policy only permits `specialUse` when **no other foreground service type covers the use case**. Android's documentation for `FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED` explicitly lists:

> Apps that have the SCHEDULE_EXACT_ALARM or USE_EXACT_ALARM permission and are using Foreground Service to continue alarms in the background, including haptics-only alarms.

That describes `AlarmRingingService` exactly, so a strict reviewer could argue `systemExempted` is the correct type and reject `specialUse`.

### Option A: keep specialUse (current submission)

Strengthen the justification so the reviewer sees a clear, user-initiated alarm clock use case.

Manifest subtype value:

```xml
<property
    android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
    android:value="Rings a user-scheduled alarm clock alarm with audio, vibration and a full-screen dismiss UI until the user dismisses or snoozes it" />
```

In the Play Console foreground service declaration, use the same wording, and attach the existing `foreground_service_demo.mp4` showing the alarm firing on a locked device and being dismissed.

### Option B: switch to systemExempted (if Play rejects specialUse)

1. In the manifest, add the permission and change the service type, removing the special use property:

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SYSTEM_EXEMPTED" />
```

```xml
<service
    android:name=".AlarmRingingService"
    android:exported="false"
    android:foregroundServiceType="systemExempted" />
```

2. Remove `FOREGROUND_SERVICE_SPECIAL_USE` from the manifest.
3. In `AlarmRingingService`, replace both uses of `ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE` with `ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED`.
4. Update the Play Console foreground service declaration to match.

`systemExempted` is only honoured while the app holds an exact alarm permission, which the required fix guarantees on API 31+.

## Files referenced

| File | Relevance |
|---|---|
| `android/app/src/main/AndroidManifest.xml` | Permissions, service type, subtype property |
| `android/app/src/main/kotlin/com/casellaweb/rolling_alarm/AlarmRingingService.kt` | Foreground service, wake lock, full-screen intent notification |
| `android/app/src/main/kotlin/com/casellaweb/rolling_alarm/AlarmReceiver.kt` | Alarm fire entry point, bridge wake lock |
| `android/app/src/main/kotlin/com/casellaweb/rolling_alarm/AlarmUiSchedulerPlugin.kt` | `setAlarmClock` scheduling, `canScheduleExactAlarms()` guard |
| `android/app/src/main/kotlin/com/casellaweb/rolling_alarm/AlarmResurrectionReceiver.kt` | Boot and package replaced rescheduling |
| `android/app/src/main/kotlin/com/casellaweb/rolling_alarm/MainActivity.kt` | Ring UI target, show when locked and turn screen on |
| `lib/services/alarm.dart` | Dart scheduling through `android_alarm_manager_plus` |
| `lib/services/notification.dart` | Full-screen intent permission prompt |
| `lib/main.dart` | Startup permission requests |
