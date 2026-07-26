package com.example.rolling_alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.AlarmManagerCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Schedules a parallel [AlarmManager.setAlarmClock] PendingIntent that fires
 * [AlarmReceiver], which escalates to [AlarmRingingService] with a full-screen
 * intent. Complements the Dart isolate callback from android_alarm_manager_plus
 * so the ring UI still appears if the Flutter engine was killed.
 *
 * Also exposes battery-optimization exemption checks required on aggressive OEMs.
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
                schedule(context, triggerAtMillis, routineId)
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
            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL = "com.example.rolling_alarm/alarm_ui_scheduler"
        private const val REQUEST_BASE = 20000

        fun schedule(context: Context, triggerAtMillis: Long, routineId: Int) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

            // Fire path: BroadcastReceiver -> ForegroundService -> FSI Activity.
            // Never start MainActivity directly from the AlarmManager operation.
            val receiverIntent = Intent(context, AlarmReceiver::class.java).apply {
                putExtra(AlarmReceiver.EXTRA_ROUTINE_ID, routineId)
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val operation = PendingIntent.getBroadcast(
                context,
                REQUEST_BASE + routineId,
                receiverIntent,
                flags
            )

            // Status-bar / lock clock affordance still needs an Activity PI.
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
            AlarmManagerCompat.setAlarmClock(
                alarmManager,
                fireAt,
                showIntent,
                operation
            )
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
        }

        fun isIgnoringBatteryOptimizations(context: Context): Boolean {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            return pm.isIgnoringBatteryOptimizations(context.packageName)
        }

        /**
         * Opens the system battery-exemption dialog. Required on Samsung / Xiaomi
         * so AlarmManager receivers and Drift isolates are not killed in Doze.
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
    }
}
