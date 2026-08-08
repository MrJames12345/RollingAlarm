package com.example.rolling_alarm

import android.app.ActivityManager
import android.app.ActivityOptions
import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Foreground service that wakes [MainActivity] for the full-page alarm UI the
 * instant an exact alarm fires. Reliable when the Flutter isolate is dead or
 * deferred by OEM battery policies.
 *
 * Android requires an ongoing FGS notification; that notification is silent and
 * is not the alarm UX.
 *
 * Locked / screen off: launch via [NotificationCompat.Builder.setFullScreenIntent]
 * only. Calling [startActivity] in that state races the FSI on many OEMs.
 *
 * Unlocked but another app is foreground: attach FSI and launch the activity
 * immediately (receiver BAL window + PendingIntent send). Without that, Android
 * blocks background activity starts and the user only hears sound/vibration.
 *
 * If the user then locks the phone (power button), [AlarmRingDisplayGate] suppresses
 * further display wake / FSI / re-launch. Alarm audio continues until dismiss.
 */
class AlarmRingingService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var wakeFallback: Runnable? = null
    private var brightWakeDowngrade: Runnable? = null
    private var activeRoutineId: Int = -1
    private var screenOffReceiverRegistered: Boolean = false

    private val screenOffReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != Intent.ACTION_SCREEN_OFF) return
            if (activeRoutineId < 0) return
            onUserLockedDuringRing()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val routineId = intent?.getIntExtra(EXTRA_ROUTINE_ID, -1) ?: -1
        if (routineId < 0) {
            stopSelf()
            return START_NOT_STICKY
        }

        // New ring session: allow one initial display wake (FSI / bright lock).
        AlarmRingDisplayGate.resetForNewRing()
        activeRoutineId = routineId
        registerScreenOffReceiver()

        val lockedOrAsleep = isLockedOrAsleep(this)
        val appForeground = isOurAppForeground(this)
        // FSI whenever we are not already showing UI (lock screen or other app).
        val useFsi = lockedOrAsleep || !appForeground

        acquireWakeLock(turnScreenOn = lockedOrAsleep)
        // Only need a bright/wakeup lock long enough for the first presentation.
        scheduleBrightWakeDowngrade()
        writeRingingPref(true)
        ensureChannel(this)

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

        // Native-first audio & vibration routing
        val audioUriRaw = intent?.getStringExtra(EXTRA_AUDIO_URI)
        val loop = intent?.getBooleanExtra(EXTRA_LOOP, true) ?: true
        val volume = intent?.getFloatExtra(EXTRA_VOLUME, 1f) ?: 1f
        val fadeInMs = intent?.getLongExtra(EXTRA_FADE_IN_MS, 0L) ?: 0L
        
        var isSilent = false
        var actualUri = audioUriRaw
        if (!audioUriRaw.isNullOrEmpty()) {
            if (audioUriRaw.startsWith("{") && audioUriRaw.contains("\"source\"")) {
                try {
                    val obj = org.json.JSONObject(audioUriRaw)
                    val source = obj.optString("source")
                    if (source == "silent") {
                        isSilent = true
                    } else if (source == "native" && obj.has("uri") && !obj.isNull("uri")) {
                        actualUri = obj.optString("uri")
                    } else {
                        actualUri = null
                    }
                } catch (_: Exception) {}
            } else if (audioUriRaw == "silent") {
                isSilent = true
            }
        }

        if (!isSilent) {
            val playUri = if (actualUri.isNullOrEmpty()) {
                android.provider.Settings.System.DEFAULT_ALARM_ALERT_URI.toString()
            } else {
                actualUri
            }
            AlarmRingtonePlayer.play(
                context = this,
                uriString = playUri,
                loop = loop,
                fadeInMs = fadeInMs,
                targetVolume = volume
            )
        }
        val vibrate = intent?.getBooleanExtra(EXTRA_VIBRATE, false) ?: false
        if (vibrate) {
            try { AlarmVibrator.start(this) } catch (_: Exception) {}
        }

        when {
            lockedOrAsleep -> {
                // Primary wake: full-screen intent. Direct startActivity here
                // suppresses FSI on many OEM / A14+ builds.
                if (!canUseFullScreenIntent()) {
                    launchRingActivity(routineId)
                }
                scheduleWakeFallback(routineId, requireStillLocked = true)
            }
            !appForeground -> {
                // Another app is open: bring Rolling Alarm over it now.
                launchRingActivity(routineId)
                scheduleWakeFallback(routineId, requireStillLocked = false)
            }
            else -> {
                // Already in our UI; Flutter presenter opens the ring page.
                launchRingActivity(routineId)
            }
        }

        return START_STICKY
    }

    override fun onDestroy() {
        unregisterScreenOffReceiver()
        AlarmRingtonePlayer.stop()
        try { AlarmVibrator.stop(this) } catch (_: Exception) {}
        cancelWakeFallback()
        cancelBrightWakeDowngrade()
        releaseWakeLock()
        activeRoutineId = -1
        AlarmRingDisplayGate.clear()
        super.onDestroy()
    }

    /**
     * User locked the phone while the alarm is still ringing. Keep FGS audio,
     * drop screen-forcing wake / FSI, and cancel re-launch retries.
     */
    private fun onUserLockedDuringRing() {
        if (activeRoutineId < 0) return
        AlarmRingDisplayGate.markUserTurnedScreenOff()
        cancelWakeFallback()
        cancelBrightWakeDowngrade()
        // PARTIAL is enough for ringtone; bright wakeup must not re-light the
        // panel after the user pressed power.
        acquireWakeLock(turnScreenOn = false, replace = true)
        demoteToQuietServiceNotification(activeRoutineId)
        try {
            sendBroadcast(Intent(ACTION_USER_LOCKED_DURING_RING).setPackage(packageName))
        } catch (_: Exception) {
        }
    }

    private fun demoteToQuietServiceNotification(routineId: Int) {
        if (routineId < 0) return
        try {
            val notification = buildServiceNotification(this, routineId, useFsi = false)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    notificationId(routineId),
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                )
            } else {
                startForeground(notificationId(routineId), notification)
            }
        } catch (_: Exception) {
        }
    }

    private fun registerScreenOffReceiver() {
        if (screenOffReceiverRegistered) return
        val filter = IntentFilter(Intent.ACTION_SCREEN_OFF)
        try {
            ContextCompat.registerReceiver(
                this,
                screenOffReceiver,
                filter,
                ContextCompat.RECEIVER_NOT_EXPORTED
            )
            screenOffReceiverRegistered = true
        } catch (_: Exception) {
        }
    }

    private fun unregisterScreenOffReceiver() {
        if (!screenOffReceiverRegistered) return
        try {
            unregisterReceiver(screenOffReceiver)
        } catch (_: Exception) {
        }
        screenOffReceiverRegistered = false
    }

    private fun acquireWakeLock(turnScreenOn: Boolean, replace: Boolean = false) {
        if (!replace && wakeLock?.isHeld == true) return
        if (replace) {
            releaseWakeLock()
        } else if (wakeLock?.isHeld == true) {
            return
        }
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        @Suppress("DEPRECATION")
        val levelAndFlags = if (turnScreenOn) {
            // Turns the display on so FSI / showWhenLocked can surface over keyguard.
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE
        } else {
            PowerManager.PARTIAL_WAKE_LOCK
        }
        wakeLock = pm.newWakeLock(levelAndFlags, WAKE_LOCK_TAG).also {
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

    private fun scheduleBrightWakeDowngrade() {
        cancelBrightWakeDowngrade()
        val task = Runnable {
            brightWakeDowngrade = null
            if (AlarmRingDisplayGate.suppressDisplayWake) return@Runnable
            // After the first presentation window, stop holding a bright lock so
            // a later power-button lock is not re-woken by ACQUIRE_CAUSES_WAKEUP.
            acquireWakeLock(turnScreenOn = false, replace = true)
        }
        brightWakeDowngrade = task
        mainHandler.postDelayed(task, BRIGHT_WAKE_HOLD_MS)
    }

    private fun cancelBrightWakeDowngrade() {
        brightWakeDowngrade?.let { mainHandler.removeCallbacks(it) }
        brightWakeDowngrade = null
    }

    private fun launchRingActivity(routineId: Int) {
        launchRingActivity(this, routineId)
    }

    private fun canUseFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return true
        }
        return try {
            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            nm.canUseFullScreenIntent()
        } catch (_: Exception) {
            true
        }
    }

    private fun scheduleWakeFallback(routineId: Int, requireStillLocked: Boolean) {
        cancelWakeFallback()
        val retry = Runnable {
            wakeFallback = null
            // User locked after first show: do not re-FSI or re-launch.
            if (AlarmRingDisplayGate.suppressDisplayWake) {
                return@Runnable
            }
            if (requireStillLocked && !isLockedOrAsleep(this)) {
                return@Runnable
            }
            if (!requireStillLocked && isOurAppForeground(this)) {
                return@Runnable
            }
            try {
                val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                nm.notify(
                    notificationId(routineId),
                    buildServiceNotification(this, routineId, useFsi = true)
                )
            } catch (_: Exception) {
            }
            launchRingActivity(routineId)
        }
        wakeFallback = retry
        mainHandler.postDelayed(retry, WAKE_FALLBACK_MS)
    }

    private fun cancelWakeFallback() {
        wakeFallback?.let { mainHandler.removeCallbacks(it) }
        wakeFallback = null
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
        const val EXTRA_AUDIO_URI = "audioUri"
        const val EXTRA_LOOP = "loop"
        const val EXTRA_VOLUME = "volume"
        const val EXTRA_FADE_IN_MS = "fadeInMs"
        const val EXTRA_VIBRATE = "vibrate"

        private const val CHANNEL_ID_SERVICE = "ra_native_alarm_fgs_v4"
        private const val CHANNEL_NAME_SERVICE = "Alarm Service"
        private const val CHANNEL_DESC_SERVICE =
            "Keeps the alarm wake service alive; ring UI is full-screen only"
        private const val CHANNEL_ID_WAKE = "ra_native_alarm_wake_v4"
        private const val CHANNEL_NAME_WAKE = "Alarm Wake"
        private const val CHANNEL_DESC_WAKE =
            "Launches the full-page alarm over the lock screen or other apps"
        private const val WAKE_LOCK_TAG = "rolling_alarm:alarm_ringing"
        private const val NOTIFICATION_BASE = 70000
        private const val REQUEST_FSI_BASE = 71000
        private const val REQUEST_CONTENT_BASE = 72000
        private const val REQUEST_LAUNCH_BASE = 73000
        private const val WAKE_FALLBACK_MS = 1_500L
        /** Hold bright/wakeup lock only for the first presentation window. */
        private const val BRIGHT_WAKE_HOLD_MS = 4_000L
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val FLUTTER_RINGING_KEY = "flutter.ra_is_ringing"
        private const val FLUTTER_WAKE_AT_KEY = "flutter.ra_alarm_wake_at_ms"

        /** Broadcast to [MainActivity] when the user powers the screen off mid-ring. */
        const val ACTION_USER_LOCKED_DURING_RING =
            "com.example.rolling_alarm.ACTION_USER_LOCKED_DURING_RING"

        fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID_SERVICE) == null) {
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

        fun notificationId(routineId: Int): Int = NOTIFICATION_BASE + routineId

        fun buildLaunchIntent(context: Context, routineId: Int): Intent {
            return Intent(context, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_NO_USER_ACTION
                )
                putExtra(MainActivity.EXTRA_ALARM_RINGING, true)
                putExtra(EXTRA_ROUTINE_ID, routineId)
            }
        }

        fun buildServiceNotification(context: Context, routineId: Int, useFsi: Boolean): Notification {
            val launchIntent = buildLaunchIntent(context, routineId)

            val contentPi = PendingIntent.getActivity(
                context,
                REQUEST_CONTENT_BASE + routineId,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val channelId = if (useFsi) CHANNEL_ID_WAKE else CHANNEL_ID_SERVICE

            val builder = NotificationCompat.Builder(context, channelId)
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
            } else {
                builder
                    .setCategory(NotificationCompat.CATEGORY_SERVICE)
                    .setPriority(NotificationCompat.PRIORITY_LOW)
                    .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            }

            return builder.build()
        }

        fun isLockedOrAsleep(context: Context): Boolean {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val km = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            val interactive = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
                pm.isInteractive
            } else {
                @Suppress("DEPRECATION")
                pm.isScreenOn
            }
            return km.isKeyguardLocked || !interactive
        }

        fun isOurAppForeground(context: Context): Boolean {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val pkg = context.packageName
            val processes = am.runningAppProcesses ?: return false
            for (process in processes) {
                if (process.processName != pkg) continue
                return process.importance <=
                    ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE
            }
            return false
        }

        fun launchRingActivity(context: Context, routineId: Int) {
            // After the user locks mid-ring, never re-force the activity on top.
            if (AlarmRingDisplayGate.suppressDisplayWake) {
                return
            }
            val launchIntent = buildLaunchIntent(context, routineId)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    val options = ActivityOptions.makeBasic().apply {
                        setPendingIntentBackgroundActivityStartMode(
                            ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
                        )
                    }
                    val pi = PendingIntent.getActivity(
                        context,
                        REQUEST_LAUNCH_BASE + routineId,
                        launchIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    pi.send(context, 0, null, null, null, null, options.toBundle())
                    return
                }
            } catch (_: Exception) {
            }
            try {
                context.startActivity(launchIntent)
            } catch (_: Exception) {
            }
        }

        fun start(context: Context, intent: Intent) {
            val serviceIntent = Intent(context, AlarmRingingService::class.java).apply {
                putExtras(intent)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        }

        fun showFallbackNotification(context: Context, intent: Intent) {
            val routineId = intent.getIntExtra(EXTRA_ROUTINE_ID, -1)
            if (routineId < 0) return
            // Mid-ring lock: never re-post FSI or re-launch the activity.
            if (AlarmRingDisplayGate.suppressDisplayWake) return
            try {
                ensureChannel(context)
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val notification = buildServiceNotification(context, routineId, useFsi = true)
                nm.notify(notificationId(routineId), notification)
                launchRingActivity(context, routineId)
            } catch (_: Exception) {}
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
