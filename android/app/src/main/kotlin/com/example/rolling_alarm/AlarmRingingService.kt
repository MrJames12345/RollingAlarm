package com.example.rolling_alarm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * Foreground service that posts a max-importance full-screen-intent notification
 * the instant an exact alarm fires. This is the reliable wake path when the
 * Flutter isolate is dead or deferred by OEM battery policies.
 */
class AlarmRingingService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val routineId = intent?.getIntExtra(EXTRA_ROUTINE_ID, -1) ?: -1
        if (routineId < 0) {
            stopSelf()
            return START_NOT_STICKY
        }

        acquireWakeLock()
        writeRingingPref(true)
        ensureChannel()

        val notification = buildFullScreenNotification(routineId)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                notificationId(routineId),
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(notificationId(routineId), notification)
        }

        return START_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            WAKE_LOCK_TAG
        ).also {
            it.setReferenceCounted(false)
            it.acquire(10 * 60_000L)
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {
        }
        wakeLock = null
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val existing = nm.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = CHANNEL_DESC
            setBypassDnd(true)
            setSound(null, null)
            enableVibration(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        nm.createNotificationChannel(channel)
    }

    private fun buildFullScreenNotification(routineId: Int): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            )
            putExtra(MainActivity.EXTRA_ALARM_RINGING, true)
            putExtra(EXTRA_ROUTINE_ID, routineId)
        }
        val fullScreenPi = PendingIntent.getActivity(
            this,
            REQUEST_FSI_BASE + routineId,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val contentPi = PendingIntent.getActivity(
            this,
            REQUEST_CONTENT_BASE + routineId,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Rolling Alarm")
            .setContentText("Alarm is ringing")
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setSound(null)
            .setContentIntent(contentPi)
            .setFullScreenIntent(fullScreenPi, true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun writeRingingPref(ringing: Boolean) {
        val editor = applicationContext
            .getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(FLUTTER_RINGING_KEY, ringing)
        if (ringing) {
            editor.putLong(FLUTTER_WAKE_AT_KEY, System.currentTimeMillis())
        } else {
            editor.remove(FLUTTER_WAKE_AT_KEY)
        }
        editor.apply()
    }

    companion object {
        const val EXTRA_ROUTINE_ID = AlarmReceiver.EXTRA_ROUTINE_ID

        private const val CHANNEL_ID = "ra_native_alarm_fsi"
        private const val CHANNEL_NAME = "Alarm Wake"
        private const val CHANNEL_DESC =
            "Native full-screen wake when an exact alarm fires"
        private const val WAKE_LOCK_TAG = "rolling_alarm:alarm_ringing"
        private const val NOTIFICATION_BASE = 70000
        private const val REQUEST_FSI_BASE = 71000
        private const val REQUEST_CONTENT_BASE = 72000
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val FLUTTER_RINGING_KEY = "flutter.ra_is_ringing"
        private const val FLUTTER_WAKE_AT_KEY = "flutter.ra_alarm_wake_at_ms"

        fun notificationId(routineId: Int): Int = NOTIFICATION_BASE + routineId

        fun start(context: Context, routineId: Int) {
            val intent = Intent(context, AlarmRingingService::class.java).apply {
                putExtra(EXTRA_ROUTINE_ID, routineId)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context, routineId: Int) {
            val nm =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(notificationId(routineId))
            try {
                context.stopService(Intent(context, AlarmRingingService::class.java))
            } catch (_: Exception) {
            }
        }
    }
}
