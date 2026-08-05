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
 *
 * Peak loudness is owned by [android.media.AudioManager.STREAM_ALARM].
 * Optional [fadeInMs] ramps Ringtone gain from 0 to [targetVolume].
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
        targetVolume: Float = 1f,
    ): Boolean {
        stop()
        val uri = Uri.parse(uriString)
        val tone = try {
            RingtoneManager.getRingtone(context.applicationContext, uri)
        } catch (e: Exception) {
            null
        } ?: return false

        val cappedTarget = targetVolume.coerceIn(0f, 1f)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            tone.audioAttributes = AudioAttributes.Builder()
                .setUsage(usage)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            tone.isLooping = loop
            tone.volume = if (fadeInMs > 0L) 0f else cappedTarget
        }

        return try {
            tone.play()
            ringtone = tone
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                if (fadeInMs > 0L) {
                    startFadeIn(fadeInMs, cappedTarget)
                } else {
                    // OEM Ringtone builds often reset gain on start (worse on
                    // longer tones). Hold full volume so playback is immediate.
                    lockFullVolume(cappedTarget)
                }
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

    private fun lockFullVolume(targetVolume: Float) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return
        try {
            ringtone?.volume = targetVolume
        } catch (_: Exception) {
        }
        val handler = Handler(Looper.getMainLooper())
        fadeHandler = handler
        val stepMs = 40L
        val holdMs = 800L
        var elapsed = 0L
        val tick = object : Runnable {
            override fun run() {
                val tone = ringtone ?: return
                try {
                    tone.volume = targetVolume
                } catch (_: Exception) {
                    return
                }
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
                val tone = ringtone ?: return
                step++
                val volume = (targetVolume * step.toFloat() / steps).coerceIn(0f, 1f)
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
