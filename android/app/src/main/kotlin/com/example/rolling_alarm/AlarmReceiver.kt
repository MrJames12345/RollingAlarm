package com.example.rolling_alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager

/**
 * Exact-alarm fire entry point from [AlarmManager.setAlarmClock].
 *
 * Must not start [MainActivity] directly from the background; Android will kill
 * or defer that path under Doze / OEM limits. Immediately acquires a
 * [PowerManager.PARTIAL_WAKE_LOCK], then escalates to [AlarmRingingService]
 * which starts the foreground service and full-page ring activity while the lock
 * is still held.
 */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val routineId = intent?.getIntExtra(EXTRA_ROUTINE_ID, -1) ?: -1
        if (routineId < 0) return

        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            WAKE_LOCK_TAG
        )
        wakeLock.setReferenceCounted(false)
        // Keep CPU awake across the FGS handoff (service acquires its own lock).
        // Timeout is the safety release; do not drop the lock before startForeground.
        wakeLock.acquire(WAKE_LOCK_TIMEOUT_MS)

        AlarmRingingService.start(context, routineId)
    }

    companion object {
        const val EXTRA_ROUTINE_ID = "routineId"
        private const val WAKE_LOCK_TAG = "rolling_alarm:alarm_receiver"
        private const val WAKE_LOCK_TIMEOUT_MS = 60_000L
    }
}
