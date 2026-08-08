package com.example.rolling_alarm

/**
 * Shared gate so a power-button lock during an active ring stops re-waking the
 * display. Native audio / FGS keeps running until snooze or dismiss.
 *
 * Reset when a new ring session starts; set when the user turns the screen off
 * while ringing; clear when the ring ends.
 */
object AlarmRingDisplayGate {
    @Volatile
    var suppressDisplayWake: Boolean = false
        private set

    fun resetForNewRing() {
        suppressDisplayWake = false
    }

    fun markUserTurnedScreenOff() {
        suppressDisplayWake = true
    }

    fun clear() {
        suppressDisplayWake = false
    }
}
