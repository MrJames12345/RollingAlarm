package com.example.rolling_alarm

import android.content.Context
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper

/**
 * Plays system ringtone / alarm URIs via [Ringtone], which is the supported
 * path for RingtoneManager content:// tones. just_audio setUrl is unreliable
 * for those URIs on many OEM builds.
 */
object AlarmRingtonePlayer {
    private var ringtone: Ringtone? = null
    private var fadeHandler: Handler? = null

    @Synchronized
    fun play(
        context: Context,
        uriString: String,
        loop: Boolean,
        usage: Int = AudioAttributes.USAGE_ALARM,
        fadeInMs: Long = 0L,
    ): Boolean {
        stop()
        val uri = Uri.parse(uriString)
        val tone = RingtoneManager.getRingtone(context.applicationContext, uri)
            ?: return false

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            tone.audioAttributes = AudioAttributes.Builder()
                .setUsage(usage)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            tone.isLooping = loop
            if (fadeInMs > 0L) {
                tone.volume = 0f
            }
        }

        return try {
            tone.play()
            ringtone = tone
            if (fadeInMs > 0L && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                startFadeIn(fadeInMs)
            }
            true
        } catch (_: Exception) {
            try {
                tone.stop()
            } catch (_: Exception) {
            }
            false
        }
    }

    @Synchronized
    fun stop() {
        fadeHandler?.removeCallbacksAndMessages(null)
        fadeHandler = null
        try {
            ringtone?.stop()
        } catch (_: Exception) {
        }
        ringtone = null
    }

    @Synchronized
    fun isPlaying(): Boolean = try {
        ringtone?.isPlaying == true
    } catch (_: Exception) {
        false
    }

    private fun startFadeIn(fadeInMs: Long) {
        val steps = 20
        val stepMs = (fadeInMs / steps).coerceAtLeast(1L)
        val handler = Handler(Looper.getMainLooper())
        fadeHandler = handler
        var step = 0
        val tick = object : Runnable {
            override fun run() {
                val tone = ringtone ?: return
                step++
                val volume = (step.toFloat() / steps).coerceIn(0f, 1f)
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        tone.volume = volume
                    }
                } catch (_: Exception) {
                    return
                }
                if (step < steps) {
                    handler.postDelayed(this, stepMs)
                }
            }
        }
        handler.postDelayed(tick, stepMs)
    }
}
