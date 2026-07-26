package com.example.rolling_alarm

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/**
 * Repeating alarm vibration using the application [Vibrator].
 *
 * Safe to call from a FlutterPlugin with application context (including
 * headless alarm isolates that lack [MainActivity]).
 */
object AlarmVibrator {
    private const val VIBRATE_MS = 600L
    private const val PAUSE_MS = 400L

    private var active: Vibrator? = null

    @Synchronized
    fun start(context: Context) {
        stop()
        val vibrator = vibrator(context) ?: return
        val pattern = longArrayOf(0L, VIBRATE_MS, PAUSE_MS)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(
                    VibrationEffect.createWaveform(pattern, 0),
                )
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(pattern, 0)
            }
            active = vibrator
        } catch (_: Exception) {
            // Vibration is best effort; never fail the alarm path.
        }
    }

    @Synchronized
    fun stop(context: Context? = null) {
        try {
            val vibrator = active ?: context?.let { vibrator(it) }
            vibrator?.cancel()
        } catch (_: Exception) {
        }
        active = null
    }

    private fun vibrator(context: Context): Vibrator? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val manager = context.applicationContext
                    .getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                manager?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.applicationContext.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
        } catch (_: Exception) {
            null
        }
    }
}
