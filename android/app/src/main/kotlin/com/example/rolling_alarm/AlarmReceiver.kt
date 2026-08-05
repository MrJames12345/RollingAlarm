package com.example.rolling_alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager

/**
 * Exact-alarm fire entry point from [AlarmManager.setAlarmClock].
 *
 * Acquires a short wake lock, starts [AlarmRingingService], and when the device
 * is unlocked immediately launches [MainActivity]. The alarm-clock broadcast
 * grants a brief background-activity exemption that is the most reliable way to
 * bring the full-page ring UI over whatever app the user currently has open.
 *
 * When locked / screen off, activity launch is left to the service full-screen
 * intent path so a direct startActivity does not cancel FSI.
 */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        // NATIVE-FIRST WAKELOCK (THE CRITICAL PATH)
        // Acquire lock instantly before doing anything else.
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            WAKE_LOCK_TAG
        )
        wakeLock.setReferenceCounted(false)
        wakeLock.acquire(WAKE_LOCK_TIMEOUT_MS)

        val routineId = intent?.getIntExtra(EXTRA_ROUTINE_ID, -1) ?: -1
        if (routineId < 0) {
            wakeLock.release()
            return
        }

        val lockedOrAsleep = AlarmRingingService.isLockedOrAsleep(context)
        val safeIntent = intent ?: Intent()
        
        try {
            AlarmRingingService.start(context, safeIntent)
        } catch (e: Exception) {
            // Android 12+ ForegroundServiceStartNotAllowedException fallback
            AlarmRingingService.showFallbackNotification(context, safeIntent)
        }

        if (!lockedOrAsleep) {
            // Use the setAlarmClock broadcast BAL window to jump over other apps.
            AlarmRingingService.launchRingActivity(context, routineId)
        }
    }

    companion object {
        const val EXTRA_ROUTINE_ID = "routineId"
        private const val WAKE_LOCK_TAG = "rolling_alarm:alarm_receiver"
        private const val WAKE_LOCK_TIMEOUT_MS = 60_000L
    }
}
