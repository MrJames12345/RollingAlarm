package com.example.rolling_alarm

import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.provider.MediaStore
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val soundChannel = "com.example.rolling_alarm/alarm_sound"
    private var pickerResult: MethodChannel.Result? = null
    private var activeRequestCode: Int = 0
    private var isAlarmRinging: Boolean = false
    /** Elapsed realtime when we last armed lock-screen overlay for an alarm. */
    private var alarmWakeElapsedMs: Long = 0L
    /** True only for a real alarm launch intent / bringToForeground, not a stale pref. */
    private var lockOverlayFromAlarmIntent: Boolean = false
    private var alarmSoundMethodChannel: MethodChannel? = null
    /** Cached side-button actions while ringing: none / snooze / dismiss. */
    private var sideButtonVolumeUp: String = ACTION_NONE
    private var sideButtonVolumeDown: String = ACTION_NONE
    private var sideButtonPower: String = ACTION_NONE

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

    private fun isDeviceKeyguardLocked(): Boolean {
        val km = getSystemService(Context.KEYGUARD_SERVICE) as? android.app.KeyguardManager
        return km?.isKeyguardLocked == true
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
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, soundChannel)
        alarmSoundMethodChannel = channel
        channel.setMethodCallHandler { call, result ->
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
                        // Dismiss / cancel clears the ringing pref first. While it
                        // is still true, ignore Flutter clears from the race where
                        // the activity woke before Drift committed IsRinging.
                        // A timed grace alone was not enough: after it expired the
                        // overlay flags dropped while sound was already playing.
                        if (readRingingPref()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        isAlarmRinging = false
                        lockOverlayFromAlarmIntent = false
                        alarmWakeElapsedMs = 0L
                        clearSideButtonActions()
                        applyLockScreenFlags(false)
                        result.success(null)
                    }
                    "dismissAlarmUI" -> {
                        // User snoozed/dismissed: drop lock-screen overlay privileges.
                        // Do not finish(); that would tear down the Flutter engine.
                        // Only background when the keyguard is still locked so it
                        // returns. If the user was already in the unlocked app,
                        // stay foregrounded so Flutter can pop the ring route
                        // without a pause/resume race that crashes on re-entry.
                        val keyguardLocked = isDeviceKeyguardLocked()
                        isAlarmRinging = false
                        lockOverlayFromAlarmIntent = false
                        writeRingingPref(false)
                        alarmWakeElapsedMs = 0L
                        clearSideButtonActions()
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
                        if (keyguardLocked) {
                            moveTaskToBack(true)
                        }
                        result.success(null)
                    }
                    "setSideButtonActions" -> {
                        val args = call.arguments as? Map<*, *>
                        sideButtonVolumeUp = normalizeSideAction(args?.get("volumeUp"))
                        sideButtonVolumeDown = normalizeSideAction(args?.get("volumeDown"))
                        sideButtonPower = normalizeSideAction(args?.get("power"))
                        result.success(null)
                    }
                    "listDeviceSounds" -> {
                        // MediaStore scans can be large; never block the UI /
                        // Flutter raster thread or the picker page freezes.
                        thread(name = "ra-list-device-sounds") {
                            try {
                                val sounds = listDeviceSounds()
                                runOnUiThread { result.success(sounds) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("list_failed", e.message, null)
                                }
                            }
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
                        val volume = (call.argument<Number>("volume")?.toFloat() ?: 1f)
                            .coerceIn(0f, 1f)
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
                                targetVolume = volume,
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
                    "setSystemAlarmVolume" -> {
                        val percentage = (call.arguments as? Number)?.toDouble()
                            ?: call.argument<Number>("volumePercentage")?.toDouble()
                        if (percentage == null) {
                            result.error("bad_args", "volumePercentage required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val audioManager =
                                getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            val maxVolume =
                                audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                            val calculatedVolume =
                                (maxVolume * percentage.coerceIn(0.0, 1.0)).toInt()
                                    .coerceIn(0, maxVolume)
                            audioManager.setStreamVolume(
                                AudioManager.STREAM_ALARM,
                                calculatedVolume,
                                0,
                            )
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("volume_failed", e.message, null)
                        }
                    }
                    "getSystemAlarmVolume" -> {
                        try {
                            val audioManager =
                                getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            val maxVolume =
                                audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                            val currentVolume =
                                audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
                            val ratio =
                                if (maxVolume > 0) {
                                    currentVolume.toDouble() / maxVolume.toDouble()
                                } else {
                                    0.0
                                }
                            result.success(ratio)
                        } catch (e: Exception) {
                            result.error("volume_failed", e.message, null)
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
                                RingtoneManager.TYPE_ALL
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

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (isAlarmRinging) {
            val action = sideActionForKey(event.keyCode)
            if (action != null && action != ACTION_NONE) {
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                    notifySideButtonAction(action)
                }
                // Consume up and repeats so the OS does not change media volume.
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun sideActionForKey(keyCode: Int): String? {
        return when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> sideButtonVolumeUp
            KeyEvent.KEYCODE_VOLUME_DOWN -> sideButtonVolumeDown
            KeyEvent.KEYCODE_POWER -> sideButtonPower
            else -> null
        }
    }

    private fun notifySideButtonAction(action: String) {
        runOnUiThread {
            try {
                alarmSoundMethodChannel?.invokeMethod("sideButtonAction", action)
            } catch (_: Exception) {
                // Engine may already be tearing down after dismiss.
            }
        }
    }

    private fun clearSideButtonActions() {
        sideButtonVolumeUp = ACTION_NONE
        sideButtonVolumeDown = ACTION_NONE
        sideButtonPower = ACTION_NONE
    }

    private fun normalizeSideAction(raw: Any?): String {
        val value = (raw as? String)?.lowercase(Locale.ROOT) ?: ACTION_NONE
        return when (value) {
            ACTION_SNOOZE, ACTION_DISMISS -> value
            else -> ACTION_NONE
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

                var displayName = "Local file"
                try {
                    contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val idx = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                            if (idx != -1) {
                                val name = cursor.getString(idx)
                                if (!name.isNullOrBlank()) displayName = name
                            }
                        }
                    }
                } catch (_: Exception) {}

                // Prefer embedded MediaStore TITLE when the content URI exposes it.
                var metadataTitle = ""
                try {
                    contentResolver.query(
                        uri,
                        arrayOf(MediaStore.Audio.Media.TITLE),
                        null,
                        null,
                        null,
                    )?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val idx = cursor.getColumnIndex(MediaStore.Audio.Media.TITLE)
                            if (idx != -1) {
                                metadataTitle = cursor.getString(idx)?.trim().orEmpty()
                            }
                        }
                    }
                } catch (_: Exception) {}

                val title = metadataTitle.ifEmpty { displayName }
                val mimeType = try {
                    contentResolver.getType(uri) ?: ""
                } catch (_: Exception) {
                    ""
                }
                val ext = displayName.substringAfterLast('.', "").lowercase()
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
                    pending.error("non_audio_file", "The selected file '$displayName' is not an audio file. Please select a valid audio file (e.g. mp3, wav, ogg).", null)
                    return
                }

                pending.success(
                    hashMapOf(
                        "uri" to uri.toString(),
                        "title" to title,
                        "displayName" to displayName,
                    ),
                )
            }
        } catch (e: Exception) {
            try {
                pending.error("picker_failed", e.message, null)
            } catch (_: Exception) {
                // Reply may already have been submitted.
            }
        }
    }

    /**
     * Builds the Device sounds list from MediaStore audio that has an OS
     * file name (DISPLAY_NAME). System ringtone titles without a file name
     * are omitted to match the picker UI.
     */
    private fun listDeviceSounds(): List<Map<String, String>> {
        val byUri = LinkedHashMap<String, Map<String, String>>()
        for (collection in mediaStoreAudioCollections()) {
            appendMediaStoreAudio(byUri, collection)
        }
        return byUri.values.sortedBy { it["title"]?.lowercase(Locale.ROOT) ?: "" }
    }

    private fun mediaStoreAudioCollections(): List<Uri> {
        val collections = mutableListOf(MediaStore.Audio.Media.INTERNAL_CONTENT_URI)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            collections.add(MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL))
        } else {
            collections.add(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI)
        }
        return collections
    }

    private fun appendMediaStoreAudio(
        byUri: LinkedHashMap<String, Map<String, String>>,
        collection: Uri,
    ) {
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.MIME_TYPE,
        )
        val selection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            "${MediaStore.Audio.Media.IS_PENDING} = 0"
        } else {
            null
        }
        try {
            contentResolver.query(
                collection,
                projection,
                selection,
                null,
                "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC",
            )?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val titleCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
                val mimeCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.MIME_TYPE)
                while (cursor.moveToNext()) {
                    val mime = cursor.getString(mimeCol)?.lowercase(Locale.ROOT)
                    if (mime != null && !mime.startsWith("audio/") && mime != "application/ogg") {
                        continue
                    }
                    val id = cursor.getLong(idCol)
                    val uri = ContentUris.withAppendedId(collection, id).toString()
                    if (byUri.containsKey(uri)) continue
                    val title = cursor.getString(titleCol)?.trim().orEmpty()
                    val displayName = cursor.getString(nameCol)?.trim().orEmpty()
                    // Picker only shows entries that have an OS file name.
                    if (displayName.isEmpty()) continue
                    // Keep metadata TITLE and OS DISPLAY_NAME separate so Flutter
                    // can show both; empty TITLE falls back to the file name.
                    val entry = hashMapOf(
                        "uri" to uri,
                        "title" to title.ifEmpty { displayName },
                        "displayName" to displayName,
                    )
                    byUri[uri] = entry
                }
            }
        } catch (_: SecurityException) {
            // READ_MEDIA_AUDIO / storage not granted yet; RingtoneManager entries remain.
        } catch (_: Exception) {
            // Ignore one bad volume so the other collections can still load.
        }
    }

    companion object {
        private const val REQUEST_RINGTONE = 9911
        private const val REQUEST_LOCAL_FILE = 9912
        private const val WAKE_STAMP_VALID_MS = 30_000L
        private const val ACTION_NONE = "none"
        private const val ACTION_SNOOZE = "snooze"
        private const val ACTION_DISMISS = "dismiss"
        const val EXTRA_ALARM_RINGING = "ra_alarm_ringing"
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val FLUTTER_RINGING_KEY = "flutter.ra_is_ringing"
        private const val FLUTTER_WAKE_AT_KEY = "flutter.ra_alarm_wake_at_ms"
    }
}
