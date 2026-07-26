package com.example.rolling_alarm

import android.content.Context
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build

/**
 * Plays system ringtone / alarm URIs via [Ringtone], which is the supported
 * path for RingtoneManager content:// tones. just_audio setUrl is unreliable
 * for those URIs on many OEM builds.
 *
 * Loudness is owned by [android.media.AudioManager.STREAM_ALARM]. The Ringtone
 * gain stays at full (1.0) so hardware alarm volume is the only control.
 */
object AlarmRingtonePlayer {
    private var ringtone: Ringtone? = null

    @Synchronized
    @Suppress("UNUSED_PARAMETER")
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
        val tone = RingtoneManager.getRingtone(context.applicationContext, uri)
            ?: return false

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            tone.audioAttributes = AudioAttributes.Builder()
                .setUsage(usage)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            tone.isLooping = loop
            // Always full internal gain; STREAM_ALARM controls perceived loudness.
            // fadeInMs / targetVolume are ignored for loudness control.
            tone.volume = 1f
        }

        return try {
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

    @Synchronized
    fun stop() {
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
}
