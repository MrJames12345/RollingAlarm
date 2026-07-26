package com.example.rolling_alarm

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val soundChannel = "com.example.rolling_alarm/alarm_sound"
    private var pickerResult: MethodChannel.Result? = null
    private var activeRequestCode: Int = 0
    private var isAlarmRinging: Boolean = false
    /** Elapsed realtime when we last armed lock-screen overlay for an alarm. */
    private var alarmWakeElapsedMs: Long = 0L
    /** True only for a real alarm launch intent / bringToForeground, not a stale pref. */
    private var lockOverlayFromAlarmIntent: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        // Apply lock-screen flags before Flutter attaches so a full-screen
        // intent cold start can appear over the keyguard immediately.
        syncRingingState(intent)
        applyLockScreenFlags(isAlarmRinging)
        super.onCreate(savedInstanceState)
        // Re-apply after window attach; some OEM builds drop pre-super flags.
        applyLockScreenFlags(isAlarmRinging)
        if (isAlarmRinging) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        syncRingingState(intent)
        applyLockScreenFlags(isAlarmRinging)
    }

    override fun onResume() {
        super.onResume()
        syncRingingState(intent)
        applyLockScreenFlags(isAlarmRinging)
    }

    private fun syncRingingState(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_ALARM_RINGING, false) == true) {
            isAlarmRinging = true
            lockOverlayFromAlarmIntent = true
            writeRingingPref(true)
            alarmWakeElapsedMs = SystemClock.elapsedRealtime()
            return
        }
        if (readRingingPref()) {
            isAlarmRinging = true
            // Full-screen intent launches lack EXTRA_ALARM_RINGING; a fresh wake
            // timestamp from Dart still means this is an alarm overlay session.
            if (isRecentAlarmWake()) {
                lockOverlayFromAlarmIntent = true
                if (alarmWakeElapsedMs == 0L) {
                    alarmWakeElapsedMs = SystemClock.elapsedRealtime()
                }
            }
        }
    }

    private fun readRingingPref(): Boolean {
        val prefs = applicationContext.getSharedPreferences(
            FLUTTER_PREFS,
            Context.MODE_PRIVATE
        )
        return prefs.getBoolean(FLUTTER_RINGING_KEY, false)
    }

    private fun isRecentAlarmWake(): Boolean {
        val prefs = applicationContext.getSharedPreferences(
            FLUTTER_PREFS,
            Context.MODE_PRIVATE
        )
        val wakeAt = prefs.getLong(FLUTTER_WAKE_AT_KEY, 0L)
        if (wakeAt <= 0L) return false
        return System.currentTimeMillis() - wakeAt < WAKE_STAMP_VALID_MS
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

    /**
     * Show the activity ON TOP of the lock screen while ringing.
     *
     * Do not call KeyguardManager.requestDismissKeyguard: on a secure lock
     * that prompts the unlock UI instead of overlaying the alarm (Samsung / A14+).
     */
    private fun applyLockScreenFlags(ringing: Boolean) {
        if (ringing) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(true)
                setTurnScreenOn(true)
            }
            // Also set legacy flags; some One UI builds honor these more reliably.
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON
            )
        } else {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(false)
                setTurnScreenOn(false)
            }
            @Suppress("DEPRECATION")
            window.clearFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(AlarmUiSchedulerPlugin())
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, soundChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bringToForeground" -> {
                        try {
                            isAlarmRinging = true
                            lockOverlayFromAlarmIntent = true
                            writeRingingPref(true)
                            alarmWakeElapsedMs = SystemClock.elapsedRealtime()
                            applyLockScreenFlags(true)
                            val launch = Intent(this@MainActivity, MainActivity::class.java).apply {
                                addFlags(
                                    Intent.FLAG_ACTIVITY_NEW_TASK or
                                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                                )
                                putExtra(EXTRA_ALARM_RINGING, true)
                            }
                            startActivity(launch)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("launch_failed", e.message, null)
                        }
                    }
                    "clearLockScreenFlags" -> {
                        // Ignore early clears while the Dart isolate may still be
                        // committing IsRinging after a lock-screen wake.
                        // Dismiss sets the ringing pref false first, so it still clears.
                        val sinceWake = SystemClock.elapsedRealtime() - alarmWakeElapsedMs
                        if (lockOverlayFromAlarmIntent &&
                            sinceWake < CLEAR_GRACE_MS &&
                            readRingingPref()
                        ) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        isAlarmRinging = false
                        lockOverlayFromAlarmIntent = false
                        writeRingingPref(false)
                        alarmWakeElapsedMs = 0L
                        applyLockScreenFlags(false)
                        result.success(null)
                    }
                    "dismissAlarmUI" -> {
                        // User snoozed/dismissed: drop lock-screen overlay privileges
                        // and send the task to the background so the keyguard returns.
                        // Do not finish(); that would tear down the Flutter engine.
                        isAlarmRinging = false
                        lockOverlayFromAlarmIntent = false
                        writeRingingPref(false)
                        alarmWakeElapsedMs = 0L
                        intent?.removeExtra(EXTRA_ALARM_RINGING)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                            setShowWhenLocked(false)
                            setTurnScreenOn(false)
                        } else {
                            @Suppress("DEPRECATION")
                            window.clearFlags(
                                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                            )
                        }
                        // Also drop keep-screen-on / allow-lock leftovers from the ring.
                        applyLockScreenFlags(false)
                        moveTaskToBack(true)
                        result.success(null)
                    }
                    "listDeviceSounds" -> {
                        try {
                            result.success(listDeviceSounds())
                        } catch (e: Exception) {
                            result.error("list_failed", e.message, null)
                        }
                    }
                    "playDeviceSound" -> {
                        val uri = call.argument<String>("uri")
                        if (uri.isNullOrBlank()) {
                            result.error("bad_args", "uri required", null)
                            return@setMethodCallHandler
                        }
                        val loop = call.argument<Boolean>("loop") ?: true
                        val fadeInMs = call.argument<Number>("fadeInMs")?.toLong() ?: 0L
                        val asAlarm = call.argument<Boolean>("asAlarm") ?: true
                        val usage = if (asAlarm) {
                            AudioAttributes.USAGE_ALARM
                        } else {
                            AudioAttributes.USAGE_MEDIA
                        }
                        try {
                            val started = AlarmRingtonePlayer.play(
                                this@MainActivity,
                                uri,
                                loop = loop,
                                usage = usage,
                                fadeInMs = fadeInMs,
                            )
                            result.success(started)
                        } catch (e: Exception) {
                            result.error("play_failed", e.message, null)
                        }
                    }
                    "stopDeviceSound" -> {
                        try {
                            AlarmRingtonePlayer.stop()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("stop_failed", e.message, null)
                        }
                    }
                    "pickDeviceSound" -> {
                        if (pickerResult != null) {
                            result.error("busy", "Picker already open", null)
                            return@setMethodCallHandler
                        }
                        pickerResult = result
                        activeRequestCode = REQUEST_RINGTONE
                        val existing = call.argument<String>("existingUri")
                        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                            putExtra(
                                RingtoneManager.EXTRA_RINGTONE_TYPE,
                                RingtoneManager.TYPE_ALARM or RingtoneManager.TYPE_RINGTONE
                            )
                            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                            putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "Alarm sound")
                            if (!existing.isNullOrEmpty()) {
                                putExtra(
                                    RingtoneManager.EXTRA_RINGTONE_EXISTING_URI,
                                    Uri.parse(existing)
                                )
                            }
                        }
                        @Suppress("DEPRECATION")
                        startActivityForResult(intent, REQUEST_RINGTONE)
                    }
                    "pickLocalFile" -> {
                        if (pickerResult != null) {
                            result.error("busy", "Picker already open", null)
                            return@setMethodCallHandler
                        }
                        pickerResult = result
                        activeRequestCode = REQUEST_LOCAL_FILE
                        // Grant flags belong on the returned URI via
                        // takePersistableUriPermission, not on this launch intent.
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "audio/*"
                            putExtra(
                                Intent.EXTRA_MIME_TYPES,
                                arrayOf("audio/*", "application/ogg", "application/x-flac", "audio/x-wav", "audio/mpeg")
                            )
                        }
                        try {
                            @Suppress("DEPRECATION")
                            startActivityForResult(intent, REQUEST_LOCAL_FILE)
                        } catch (e: Exception) {
                            pickerResult = null
                            activeRequestCode = 0
                            result.error("launch_failed", "Could not open file picker: ${e.message}", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // Handle our pickers before super so cancel (null data) is not
        // delivered to every Flutter plugin. Some plugins crash on null data.
        if (requestCode == REQUEST_RINGTONE || requestCode == REQUEST_LOCAL_FILE) {
            handlePickerActivityResult(requestCode, resultCode, data)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun handlePickerActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        val pending = pickerResult
        val currentRequest = activeRequestCode
        pickerResult = null
        activeRequestCode = 0
        if (pending == null) return

        try {
            if (resultCode != RESULT_OK || data == null) {
                pending.success(null)
                return
            }
            if (currentRequest == REQUEST_RINGTONE || requestCode == REQUEST_RINGTONE) {
                @Suppress("DEPRECATION")
                val uri =
                    data.getParcelableExtra<Uri>(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
                if (uri == null) {
                    pending.success(null)
                    return
                }
                val title = RingtoneManager.getRingtone(this, uri)?.getTitle(this) ?: "Device sound"
                pending.success(hashMapOf("uri" to uri.toString(), "title" to title))
                return
            }

            if (currentRequest == REQUEST_LOCAL_FILE || requestCode == REQUEST_LOCAL_FILE) {
                val uri = data.data
                if (uri == null) {
                    pending.success(null)
                    return
                }
                try {
                    var takeFlags = data.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION
                    if (takeFlags == 0) {
                        takeFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION
                    }
                    contentResolver.takePersistableUriPermission(uri, takeFlags)
                } catch (_: Exception) {}

                var title = "Local file"
                try {
                    contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val idx = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                            if (idx != -1) {
                                val name = cursor.getString(idx)
                                if (!name.isNullOrBlank()) title = name
                            }
                        }
                    }
                } catch (_: Exception) {}

                val mimeType = try {
                    contentResolver.getType(uri) ?: ""
                } catch (_: Exception) {
                    ""
                }
                val ext = title.substringAfterLast('.', "").lowercase()
                val audioExtensions = setOf("mp3", "wav", "ogg", "flac", "m4a", "aac", "wma", "opus", "mid", "midi", "amr", "aiff", "mpga", "m3u", "aif")
                val nonAudioExtensions = setOf("jpg", "jpeg", "png", "gif", "bmp", "webp", "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "csv", "zip", "rar", "7z", "tar", "gz", "mp4", "mkv", "avi", "mov", "wmv", "flv", "webm", "exe", "apk", "bin", "iso", "xml", "html", "json")

                val isAudioMime = mimeType.startsWith("audio/", ignoreCase = true) ||
                    mimeType.equals("application/ogg", ignoreCase = true) ||
                    mimeType.equals("application/x-flac", ignoreCase = true)
                val isAudioExt = audioExtensions.contains(ext)
                val isNonAudioExt = nonAudioExtensions.contains(ext) ||
                    mimeType.startsWith("image/", ignoreCase = true) ||
                    mimeType.startsWith("video/", ignoreCase = true) ||
                    mimeType.startsWith("text/", ignoreCase = true)

                if (isNonAudioExt || (!isAudioMime && !isAudioExt && ext.isNotEmpty())) {
                    pending.error("non_audio_file", "The selected file '$title' is not an audio file. Please select a valid audio file (e.g. mp3, wav, ogg).", null)
                    return
                }

                pending.success(hashMapOf("uri" to uri.toString(), "title" to title))
            }
        } catch (e: Exception) {
            try {
                pending.error("picker_failed", e.message, null)
            } catch (_: Exception) {
                // Reply may already have been submitted.
            }
        }
    }

    private fun listDeviceSounds(): List<Map<String, String>> {
        val manager = RingtoneManager(this)
        manager.setType(RingtoneManager.TYPE_ALARM or RingtoneManager.TYPE_RINGTONE)
        val cursor = manager.cursor
        val sounds = ArrayList<Map<String, String>>()
        while (cursor.moveToNext()) {
            val title = cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX) ?: continue
            val uri = manager.getRingtoneUri(cursor.position)?.toString() ?: continue
            sounds.add(hashMapOf("title" to title, "uri" to uri))
        }
        cursor.close()
        return sounds
    }

    companion object {
        private const val REQUEST_RINGTONE = 9911
        private const val REQUEST_LOCAL_FILE = 9912
        private const val CLEAR_GRACE_MS = 5_000L
        private const val WAKE_STAMP_VALID_MS = 30_000L
        const val EXTRA_ALARM_RINGING = "ra_alarm_ringing"
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val FLUTTER_RINGING_KEY = "flutter.ra_is_ringing"
        private const val FLUTTER_WAKE_AT_KEY = "flutter.ra_alarm_wake_at_ms"
    }
}
