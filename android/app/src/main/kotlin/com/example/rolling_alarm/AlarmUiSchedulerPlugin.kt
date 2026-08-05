package com.example.rolling_alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Schedules alarms exclusively via [AlarmManager.setAlarmClock] so the OS
 * treats them like the system Clock app (Doze / OEM idle exempt, status bar
 * upcoming-alarm affordance).
 *
 * Fire path: [AlarmReceiver] -> [AlarmRingingService] FGS + full-screen intent.
 * Complements the Dart isolate callback from android_alarm_manager_plus so the
 * ring UI still appears if the Flutter engine was killed.
 *
 * Also exposes aggressive battery-optimization exemption checks required on
 * Samsung / Xiaomi and similar OEMs.
 */
class AlarmUiSchedulerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var appContext: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = appContext
        if (context == null) {
            result.error("no_context", "Plugin not attached", null)
            return
        }
        when (call.method) {
            "schedule" -> {
                val triggerAtMillis = call.argument<Number>("triggerAtMillis")?.toLong()
                val routineId = call.argument<Number>("routineId")?.toInt()
                if (triggerAtMillis == null || routineId == null) {
                    result.error("bad_args", "triggerAtMillis and routineId required", null)
                    return
                }
                
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    if (!alarmManager.canScheduleExactAlarms()) {
                        result.error("exact_alarm_denied", "Exact alarm permission is denied.", null)
                        return
                    }
                }
                
                val audioUri = call.argument<String>("audioUri")
                val loop = call.argument<Boolean>("loop") ?: true
                val volume = call.argument<Number>("volume")?.toFloat() ?: 1f
                val fadeInMs = call.argument<Number>("fadeInMs")?.toLong() ?: 0L
                val vibrate = call.argument<Boolean>("vibrate") ?: false

                schedule(context, triggerAtMillis, routineId, audioUri, loop, volume, fadeInMs, vibrate)
                result.success(null)
            }
            "cancel" -> {
                val routineId = call.argument<Number>("routineId")?.toInt()
                if (routineId == null) {
                    result.error("bad_args", "routineId required", null)
                    return
                }
                cancel(context, routineId)
                result.success(null)
            }
            "stopRinging" -> {
                val routineId = call.argument<Number>("routineId")?.toInt() ?: -1
                AlarmRingingService.stop(context, routineId)
                result.success(null)
            }
            "isIgnoringBatteryOptimizations" -> {
                result.success(isIgnoringBatteryOptimizations(context))
            }
            "requestIgnoreBatteryOptimizations" -> {
                result.success(requestIgnoreBatteryOptimizations(context))
            }
            "ensureIgnoringBatteryOptimizations" -> {
                // Combined check + forceful prompt for create / toggle paths.
                result.success(ensureIgnoringBatteryOptimizations(context))
            }
            "startVibration" -> {
                try {
                    AlarmVibrator.start(context)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("vibrate_failed", e.message, null)
                }
            }
            "stopVibration" -> {
                try {
                    AlarmVibrator.stop(context)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("vibrate_stop_failed", e.message, null)
                }
            }
            "refreshWidgets" -> {
                try {
                    WidgetRefresh.refreshAll(context)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("widget_refresh_failed", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL = "com.example.rolling_alarm/alarm_ui_scheduler"
        private const val REQUEST_BASE = 20000
        const val PREFS_NAME = "ra_native_alarms"

        /**
         * Arms a system-level alarm-clock timer. Uses
         * [AlarmManager.setAlarmClock] with an explicit [AlarmManager.AlarmClockInfo]
         * (never setExact / setExactAndAllowWhileIdle).
         */
        fun schedule(
            context: Context, 
            triggerAtMillis: Long, 
            routineId: Int,
            audioUri: String? = null,
            loop: Boolean = true,
            volume: Float = 1f,
            fadeInMs: Long = 0L,
            vibrate: Boolean = false
        ) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

            // Operation PI: BroadcastReceiver -> ForegroundService -> FSI Activity.
            // Never start MainActivity directly from the AlarmManager fire path.
            val receiverIntent = Intent(context, AlarmReceiver::class.java).apply {
                putExtra(AlarmReceiver.EXTRA_ROUTINE_ID, routineId)
                if (audioUri != null) putExtra("audioUri", audioUri)
                putExtra("loop", loop)
                putExtra("volume", volume)
                putExtra("fadeInMs", fadeInMs)
                putExtra("vibrate", vibrate)
            }
            val operation = PendingIntent.getBroadcast(
                context,
                REQUEST_BASE + routineId,
                receiverIntent,
                flags
            )

            // Show PI: system status-bar / lock clock tap opens the app.
            val showLaunch = Intent(context, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                )
                putExtra(MainActivity.EXTRA_ALARM_RINGING, true)
                putExtra(AlarmReceiver.EXTRA_ROUTINE_ID, routineId)
            }
            val showIntent = PendingIntent.getActivity(
                context,
                REQUEST_BASE + routineId + 5000,
                showLaunch,
                flags
            )

            val fireAt = triggerAtMillis.coerceAtLeast(System.currentTimeMillis() + 500L)
            val clockInfo = AlarmManager.AlarmClockInfo(fireAt, showIntent)
            alarmManager.setAlarmClock(clockInfo, operation)
            
            saveAlarmToPrefs(context, triggerAtMillis, routineId, audioUri, loop, volume, fadeInMs, vibrate)
        }

        fun cancel(context: Context, routineId: Int) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val receiverIntent = Intent(context, AlarmReceiver::class.java)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val operation = PendingIntent.getBroadcast(
                context,
                REQUEST_BASE + routineId,
                receiverIntent,
                flags
            )
            alarmManager.cancel(operation)
            operation.cancel()
            AlarmRingingService.stop(context, routineId)
            removeAlarmFromPrefs(context, routineId)
        }

        fun isIgnoringBatteryOptimizations(context: Context): Boolean {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            return pm.isIgnoringBatteryOptimizations(context.packageName)
        }

        private fun saveAlarmToPrefs(
            context: Context, 
            triggerAtMillis: Long, 
            routineId: Int,
            audioUri: String?,
            loop: Boolean,
            volume: Float,
            fadeInMs: Long,
            vibrate: Boolean
        ) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val json = org.json.JSONObject().apply {
                put("triggerAtMillis", triggerAtMillis)
                put("routineId", routineId)
                if (audioUri != null) put("audioUri", audioUri)
                put("loop", loop)
                put("volume", volume.toDouble())
                put("fadeInMs", fadeInMs)
                put("vibrate", vibrate)
            }
            prefs.edit().putString(routineId.toString(), json.toString()).apply()
        }

        private fun removeAlarmFromPrefs(context: Context, routineId: Int) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().remove(routineId.toString()).apply()
        }

        /**
         * Forcefully opens [Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS]
         * when the app is still subject to Doze / OEM battery throttling.
         *
         * Returns true if already exempt or the system dialog / settings page
         * was launched successfully.
         */
        fun requestIgnoreBatteryOptimizations(context: Context): Boolean {
            if (isIgnoringBatteryOptimizations(context)) {
                return true
            }
            return try {
                val intent = Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                ).apply {
                    data = Uri.parse("package:${context.packageName}")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                true
            } catch (_: Exception) {
                try {
                    val fallback = Intent(
                        Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
                    ).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(fallback)
                    true
                } catch (_: Exception) {
                    false
                }
            }
        }

        /**
         * Check then prompt. Used by Dart create / toggle / schedule paths so
         * the user cannot silently remain under battery restrictions.
         */
        fun ensureIgnoringBatteryOptimizations(context: Context): Boolean {
            if (isIgnoringBatteryOptimizations(context)) {
                return true
            }
            return requestIgnoreBatteryOptimizations(context)
        }
    }
}
