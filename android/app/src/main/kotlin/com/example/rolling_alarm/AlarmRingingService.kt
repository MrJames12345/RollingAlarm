package com.example.rolling_alarm

import android.app.KeyguardManager
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
 * Foreground service that wakes [MainActivity] for the full-page alarm UI the
 * instant an exact alarm fires. Reliable when the Flutter isolate is dead or
 * deferred by OEM battery policies.
 *
 * Android requires an ongoing FGS notification; that notification is silent and
 * is not the alarm UX. The activity is always started so the user sees the
 * full-page ring screen instead of a heads-up banner.
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

        val notification = buildServiceNotification(routineId)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                notificationId(routineId),
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(notificationId(routineId), notification)
        }

        // Always open the full-page alarm; do not rely on heads-up demotion of FSI.
        launchRingActivity(routineId)

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
        if (nm.getNotificationChannel(CHANNEL_ID_SERVICE) == null) {
            // Low importance: required FGS entry only, never a heads-up banner.
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID_SERVICE,
                    CHANNEL_NAME_SERVICE,
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = CHANNEL_DESC_SERVICE
                    setBypassDnd(false)
                    setSound(null, null)
                    enableVibration(false)
                    setShowBadge(false)
                    lockscreenVisibility = Notification.VISIBILITY_SECRET
                }
            )
        }
        if (nm.getNotificationChannel(CHANNEL_ID_WAKE) == null) {
            // High importance only for locked / screen-off FSI backup.
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID_WAKE,
                    CHANNEL_NAME_WAKE,
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = CHANNEL_DESC_WAKE
                    setBypassDnd(true)
                    setSound(null, null)
                    enableVibration(false)
                    setShowBadge(false)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
            )
        }
    }

    private fun buildLaunchIntent(routineId: Int): Intent {
        return Intent(this, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            )
            putExtra(MainActivity.EXTRA_ALARM_RINGING, true)
            putExtra(EXTRA_ROUTINE_ID, routineId)
        }
    }

    private fun launchRingActivity(routineId: Int) {
        try {
            startActivity(buildLaunchIntent(routineId))
        } catch (_: Exception) {
            // Fall back to full-screen intent on the FGS notification below.
        }
    }

    private fun needsFullScreenIntentBackup(): Boolean {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        val km = getSystemService(KEYGUARD_SERVICE) as KeyguardManager
        val interactive = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
            pm.isInteractive
        } else {
            @Suppress("DEPRECATION")
            pm.isScreenOn
        }
        return km.isKeyguardLocked || !interactive
    }

    /**
     * Minimal ongoing notification required to keep the FGS alive.
     * Unlocked: low-importance silent entry (no heads-up). Locked / screen off:
     * high-importance FSI backup so Android can still launch the full-page UI.
     */
    private fun buildServiceNotification(routineId: Int): Notification {
        val launchIntent = buildLaunchIntent(routineId)
        val contentPi = PendingIntent.getActivity(
            this,
            REQUEST_CONTENT_BASE + routineId,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val useFsi = needsFullScreenIntentBackup()
        val channelId = if (useFsi) CHANNEL_ID_WAKE else CHANNEL_ID_SERVICE

        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Rolling Alarm")
            .setContentText("Alarm is ringing")
            .setOngoing(true)
            .setAutoCancel(false)
            .setSilent(true)
            .setSound(null)
            .setContentIntent(contentPi)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)

        if (useFsi) {
            val fullScreenPi = PendingIntent.getActivity(
                this,
                REQUEST_FSI_BASE + routineId,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setFullScreenIntent(fullScreenPi, true)
        } else {
            builder
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setVisibility(NotificationCompat.VISIBILITY_SECRET)
        }

        return builder.build()
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

        // Low-importance FGS channel for unlocked alarms (no heads-up).
        private const val CHANNEL_ID_SERVICE = "ra_native_alarm_fgs_v3"
        private const val CHANNEL_NAME_SERVICE = "Alarm Service"
        private const val CHANNEL_DESC_SERVICE =
            "Keeps the alarm wake service alive; ring UI is full-screen only"
        // High-importance wake channel only when locked / screen off (FSI backup).
        private const val CHANNEL_ID_WAKE = "ra_native_alarm_wake_v3"
        private const val CHANNEL_NAME_WAKE = "Alarm Wake"
        private const val CHANNEL_DESC_WAKE =
            "Launches the full-page alarm when the device is locked or asleep"
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
