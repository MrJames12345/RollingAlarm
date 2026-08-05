package com.example.rolling_alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject

class AlarmResurrectionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action
        if (action == Intent.ACTION_BOOT_COMPLETED || 
            action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == "com.htc.intent.action.QUICKBOOT_POWERON") {
            
            try {
                rescheduleAlarms(context)
            } catch (_: Exception) {
                // Do not crash the OS during boot sequence
            }
        }
    }

    private fun rescheduleAlarms(context: Context) {
        val prefs = context.getSharedPreferences(AlarmUiSchedulerPlugin.PREFS_NAME, Context.MODE_PRIVATE)
        val allEntries = prefs.all
        val now = System.currentTimeMillis()
        val editor = prefs.edit()

        for ((key, value) in allEntries) {
            if (value !is String) continue
            try {
                val json = JSONObject(value)
                val triggerAtMillis = json.optLong("triggerAtMillis", -1L)
                val routineId = json.optInt("routineId", -1)

                if (routineId == -1 || triggerAtMillis == -1L) {
                    editor.remove(key)
                    continue
                }

                // If the alarm is in the past, discard it
                if (triggerAtMillis < now) {
                    editor.remove(key)
                    continue
                }

                val audioUri = if (json.has("audioUri") && !json.isNull("audioUri")) json.getString("audioUri") else null
                val loop = json.optBoolean("loop", true)
                val volume = json.optDouble("volume", 1.0).toFloat()
                val fadeInMs = json.optLong("fadeInMs", 0L)
                val vibrate = json.optBoolean("vibrate", false)

                // Re-register the alarm clock natively
                AlarmUiSchedulerPlugin.schedule(
                    context = context,
                    triggerAtMillis = triggerAtMillis,
                    routineId = routineId,
                    audioUri = audioUri,
                    loop = loop,
                    volume = volume,
                    fadeInMs = fadeInMs,
                    vibrate = vibrate
                )
            } catch (_: Exception) {
                // If a single entry fails to parse, just drop it but continue processing others
                editor.remove(key)
            }
        }
        editor.apply()
    }
}
