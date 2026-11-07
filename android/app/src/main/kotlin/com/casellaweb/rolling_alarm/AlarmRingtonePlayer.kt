package com.casellaweb.rolling_alarm

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.io.File

/**
 * Single owner of alarm and device sound playback for the whole process.
 *
 * [AlarmRingingService] and the Flutter ring page both route through here, so
 * whichever starts second sees the same source already playing and leaves it
 * alone instead of replacing it with a different tone.
 *
 * Playback prefers [MediaPlayer], which plays the exact URI or fails loudly.
 * [Ringtone] is only a secondary attempt because it silently substitutes the
 * system default tone when it cannot open a URI.
 *
 * Peak loudness is owned by [AudioManager.STREAM_ALARM].
 * Optional fadeInMs ramps player gain from 0 to the target volume.
 */
object AlarmRingtonePlayer {
    /** Source marker for the bundled Flutter asset tone. */
    const val BUNDLED_DEFAULT_SOURCE = "ra-asset:default_alarm"

    private const val BUNDLED_DEFAULT_ASSET = "flutter_assets/assets/audio/default_alarm.mp3"
    private const val BUNDLED_DEFAULT_CACHE_NAME = "ra_default_alarm.mp3"

    private var mediaPlayer: MediaPlayer? = null
    private var ringtone: Ringtone? = null
    private var fadeHandler: Handler? = null
    private var currentSource: String? = null
    private var currentUsage: Int = AudioAttributes.USAGE_ALARM
    private var appContext: Context? = null
    private var focusRequest: AudioFocusRequest? = null
    private val focusListener = AudioManager.OnAudioFocusChangeListener { }

    /**
     * Resolves the stored routine AudioUri (JSON envelope or legacy plain URI)
     * into a playable source, [BUNDLED_DEFAULT_SOURCE], or null for silent.
     *
     * Must mirror RA_AlarmSound.decode / storage keys in Dart.
     */
    fun resolveSource(raw: String?): String? {
        val value = raw?.trim().orEmpty()
        if (value.isEmpty() || value == "default_ringtone") return BUNDLED_DEFAULT_SOURCE
        if (value == "silent") return null
        if (value.startsWith("{")) {
            return try {
                val obj = org.json.JSONObject(value)
                val uri = if (obj.has("uri") && !obj.isNull("uri")) {
                    obj.optString("uri").trim()
                } else {
                    ""
                }
                when (obj.optString("source")) {
                    "silent" -> null
                    "device", "local" -> uri.ifEmpty { BUNDLED_DEFAULT_SOURCE }
                    else -> BUNDLED_DEFAULT_SOURCE
                }
            } catch (_: Exception) {
                BUNDLED_DEFAULT_SOURCE
            }
        }
        return value
    }

    /**
     * Plays a stored routine AudioUri on the alarm stream with a fallback chain
     * of chosen sound, bundled tone, then the system default alarm.
     *
     * Returns true when audio started or the selection is silent.
     */
    @Synchronized
    fun playAlarm(
        context: Context,
        rawAudioUri: String?,
        loop: Boolean = true,
        fadeInMs: Long = 0L,
    ): Boolean {
        val source = resolveSource(rawAudioUri)
        if (source == null) {
            stop()
            return true
        }
        return play(
            context = context,
            uriString = source,
            loop = loop,
            usage = AudioAttributes.USAGE_ALARM,
            fadeInMs = fadeInMs,
            targetVolume = 1f,
            fallbackToDefault = true,
        )
    }

    @Synchronized
    fun play(
        context: Context,
        uriString: String,
        loop: Boolean,
        usage: Int = AudioAttributes.USAGE_ALARM,
        fadeInMs: Long = 0L,
        targetVolume: Float = 1f,
        fallbackToDefault: Boolean = false,
    ): Boolean {
        if (currentSource == uriString && currentUsage == usage && isPlayingInternal()) {
            return true
        }
        stop()
        val ctx = context.applicationContext
        appContext = ctx
        val cappedTarget = targetVolume.coerceIn(0f, 1f)
        val initialGain = if (fadeInMs > 0L) 0f else cappedTarget

        val candidates = mutableListOf(uriString)
        if (fallbackToDefault) {
            if (uriString != BUNDLED_DEFAULT_SOURCE) candidates.add(BUNDLED_DEFAULT_SOURCE)
            candidates.add(android.provider.Settings.System.DEFAULT_ALARM_ALERT_URI.toString())
        }

        var started = false
        for (candidate in candidates) {
            if (startMediaPlayer(ctx, candidate, loop, usage, initialGain, fallbackToDefault)) {
                started = true
                break
            }
            if (candidate != BUNDLED_DEFAULT_SOURCE &&
                startRingtone(ctx, candidate, loop, usage, initialGain)
            ) {
                started = true
                break
            }
        }
        if (!started) return false

        currentSource = uriString
        currentUsage = usage
        if (usage == AudioAttributes.USAGE_ALARM) requestFocus(ctx)
        if (fadeInMs > 0L) {
            startFadeIn(fadeInMs, cappedTarget)
        } else if (ringtone != null) {
            // OEM Ringtone builds often reset gain on start. Hold full volume.
            lockFullVolume(cappedTarget)
        }
        return true
    }

    @Synchronized
    fun stop() {
        fadeHandler?.removeCallbacksAndMessages(null)
        fadeHandler = null
        try {
            mediaPlayer?.stop()
        } catch (_: Exception) {
        }
        try {
            mediaPlayer?.release()
        } catch (_: Exception) {
        }
        mediaPlayer = null
        try {
            ringtone?.stop()
        } catch (_: Exception) {
        }
        ringtone = null
        currentSource = null
        abandonFocus()
    }

    @Synchronized
    fun isPlaying(): Boolean = isPlayingInternal()

    /** Sets [AudioManager.STREAM_ALARM] to [percentage] (0.0 to 1.0) of max. */
    fun setAlarmStreamVolume(context: Context, percentage: Double) {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        val calculatedVolume = (maxVolume * percentage.coerceIn(0.0, 1.0)).toInt()
            .coerceIn(0, maxVolume)
        audioManager.setStreamVolume(AudioManager.STREAM_ALARM, calculatedVolume, 0)
    }

    private fun isPlayingInternal(): Boolean {
        try {
            if (mediaPlayer?.isPlaying == true) return true
        } catch (_: Exception) {
        }
        return try {
            ringtone?.isPlaying == true
        } catch (_: Exception) {
            false
        }
    }

    private fun audioAttributes(usage: Int): AudioAttributes = AudioAttributes.Builder()
        .setUsage(usage)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    private fun startMediaPlayer(
        context: Context,
        source: String,
        loop: Boolean,
        usage: Int,
        gain: Float,
        recoverOnError: Boolean,
    ): Boolean {
        val player = MediaPlayer()
        return try {
            player.setAudioAttributes(audioAttributes(usage))
            if (source == BUNDLED_DEFAULT_SOURCE) {
                setBundledDataSource(context, player)
            } else {
                player.setDataSource(context, Uri.parse(source))
            }
            player.isLooping = loop
            player.setVolume(gain, gain)
            player.prepare()
            if (recoverOnError) {
                player.setOnErrorListener { mp, _, _ ->
                    onPlaybackError(mp)
                    true
                }
            }
            player.start()
            mediaPlayer = player
            true
        } catch (_: Exception) {
            try {
                player.release()
            } catch (_: Exception) {
            }
            false
        }
    }

    /**
     * Flutter assets live inside the APK. Prefer a direct file descriptor and
     * fall back to a cached copy when the asset is stored compressed.
     */
    private fun setBundledDataSource(context: Context, player: MediaPlayer) {
        try {
            context.assets.openFd(BUNDLED_DEFAULT_ASSET).use { afd ->
                player.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            }
            return
        } catch (_: Exception) {
        }
        val cached = File(context.cacheDir, BUNDLED_DEFAULT_CACHE_NAME)
        if (!cached.exists() || cached.length() == 0L) {
            context.assets.open(BUNDLED_DEFAULT_ASSET).use { input ->
                cached.outputStream().use { output -> input.copyTo(output) }
            }
        }
        player.setDataSource(cached.absolutePath)
    }

    private fun startRingtone(
        context: Context,
        source: String,
        loop: Boolean,
        usage: Int,
        gain: Float,
    ): Boolean {
        val tone = try {
            RingtoneManager.getRingtone(context, Uri.parse(source))
        } catch (_: Exception) {
            null
        } ?: return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                tone.audioAttributes = audioAttributes(usage)
                tone.isLooping = loop
                tone.volume = gain
            } else {
                @Suppress("DEPRECATION")
                tone.streamType = if (usage == AudioAttributes.USAGE_ALARM) {
                    AudioManager.STREAM_ALARM
                } else {
                    AudioManager.STREAM_MUSIC
                }
            }
            tone.play()
            ringtone = tone
            true
        } catch (_: Exception) {
            try {
                tone.stop()
            } catch (_: Exception) {
            }
            false
        }
    }

    /** A chosen sound that dies mid-ring must not leave the alarm silent. */
    @Synchronized
    private fun onPlaybackError(failed: MediaPlayer) {
        if (failed !== mediaPlayer) return
        val ctx = appContext ?: return
        val failedSource = currentSource
        val usage = currentUsage
        stop()
        val retry = if (failedSource == BUNDLED_DEFAULT_SOURCE) {
            android.provider.Settings.System.DEFAULT_ALARM_ALERT_URI.toString()
        } else {
            BUNDLED_DEFAULT_SOURCE
        }
        play(ctx, retry, loop = true, usage = usage, fallbackToDefault = true)
    }

    private fun applyGain(volume: Float) {
        try {
            mediaPlayer?.setVolume(volume, volume)
        } catch (_: Exception) {
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                ringtone?.volume = volume
            } catch (_: Exception) {
            }
        }
    }

    private fun lockFullVolume(targetVolume: Float) {
        applyGain(targetVolume)
        val handler = Handler(Looper.getMainLooper())
        fadeHandler = handler
        val stepMs = 40L
        val holdMs = 800L
        var elapsed = 0L
        val tick = object : Runnable {
            override fun run() {
                if (mediaPlayer == null && ringtone == null) return
                applyGain(targetVolume)
                elapsed += stepMs
                if (elapsed < holdMs) {
                    handler.postDelayed(this, stepMs)
                }
            }
        }
        handler.postDelayed(tick, stepMs)
    }

    private fun startFadeIn(fadeInMs: Long, targetVolume: Float) {
        val steps = 20
        val stepMs = (fadeInMs / steps).coerceAtLeast(1L)
        val handler = Handler(Looper.getMainLooper())
        fadeHandler = handler
        var step = 0
        val tick = object : Runnable {
            override fun run() {
                if (mediaPlayer == null && ringtone == null) return
                step++
                applyGain((targetVolume * step.toFloat() / steps).coerceIn(0f, 1f))
                if (step < steps) {
                    handler.postDelayed(this, stepMs)
                }
            }
        }
        handler.postDelayed(tick, stepMs)
    }

    /** Pauses other media while the alarm rings, like the system Clock app. */
    private fun requestFocus(context: Context) {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                    .setAudioAttributes(audioAttributes(AudioAttributes.USAGE_ALARM))
                    .setOnAudioFocusChangeListener(focusListener)
                    .build()
                am.requestAudioFocus(request)
                focusRequest = request
            } else {
                @Suppress("DEPRECATION")
                am.requestAudioFocus(
                    focusListener,
                    AudioManager.STREAM_ALARM,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
                )
            }
        } catch (_: Exception) {
        }
    }

    private fun abandonFocus() {
        val ctx = appContext ?: return
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                focusRequest?.let { am.abandonAudioFocusRequest(it) }
            } else {
                @Suppress("DEPRECATION")
                am.abandonAudioFocus(focusListener)
            }
        } catch (_: Exception) {
        }
        focusRequest = null
    }
}
