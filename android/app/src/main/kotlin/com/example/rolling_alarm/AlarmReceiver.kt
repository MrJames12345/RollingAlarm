package com.example.rolling_alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager

/**
 * Exact-alarm fire entry point. Must not start [MainActivity] directly from the
 * background; Android will kill or defer that path under Doze / OEM limits.
 * Immediately escalates to [AlarmRingingService] under a short wake lock.
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
        wakeLock.acquire(60_000L)

        try {
            AlarmRingingService.start(context, routineId)
        } finally {
            // Service acquires its own lock; release the receiver hold promptly.
            if (wakeLock.isHeld) {
                wakeLock.release()
            }
        }
    }

    companion object {
        const val EXTRA_ROUTINE_ID = "routineId"
        private const val WAKE_LOCK_TAG = "rolling_alarm:alarm_receiver"
    }
}
