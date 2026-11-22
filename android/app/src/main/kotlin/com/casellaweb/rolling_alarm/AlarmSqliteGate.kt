package com.casellaweb.rolling_alarm

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import java.io.File

/**
 * Read-only SQLite guard against Drift's `rolling_alarm.db`.
 *
 * Prevents native [AlarmRingingService] / [AlarmReceiver] / [AlarmResurrectionReceiver]
 * from waking the screen or playing audio for routines that were muted, paused,
 * or soft-deleted before a pending `setAlarmClock` fired.
 */
object AlarmSqliteGate {
    /**
     * Returns `true` when [routineId] must NOT ring natively:
     * - routine row is missing
     * - `routines.deleted == 1`
     * - `routines.is_active == 0`
     * - `routine_states.deleted == 1` or `routine_states.muted_at != null`
     *
     * Fails open (`false`) if the database file cannot be resolved or opened so
     * transient storage errors never silence a real alarm.
     */
    fun shouldSuppressRing(context: Context, routineId: Int): Boolean {
        if (routineId < 0) return true
        val path = dbPath(context) ?: return false
        val db = openDb(path) ?: return false
        return try {
            db.use { sqlite ->
                val routineRow = sqlite.rawQuery(
                    """
                    SELECT deleted, is_active
                    FROM routines
                    WHERE id = ?
                    LIMIT 1
                    """.trimIndent(),
                    arrayOf(routineId.toString()),
                ).use { cursor ->
                    if (!cursor.moveToFirst()) return true
                    val deleted = cursor.getInt(0) == 1
                    val isActive = cursor.getInt(1) == 1
                    Pair(deleted, isActive)
                }

                if (routineRow.first || !routineRow.second) {
                    return true
                }

                sqlite.rawQuery(
                    """
                    SELECT deleted, muted_at
                    FROM routine_states
                    WHERE routine_id = ?
                    LIMIT 1
                    """.trimIndent(),
                    arrayOf(routineId.toString()),
                ).use { cursor ->
                    if (!cursor.moveToFirst()) return false
                    val stateDeleted = cursor.getInt(0) == 1
                    val isMuted = !cursor.isNull(1)
                    stateDeleted || isMuted
                }
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun dbPath(context: Context): String? {
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE,
        )
        val fromPrefs = prefs.getString("flutter.ra_db_path", null)
            ?: prefs.getString("ra_db_path", null)
        if (!fromPrefs.isNullOrBlank()) return fromPrefs

        val fallback = File(context.dataDir, "app_flutter/rolling_alarm.db")
        return if (fallback.exists()) fallback.absolutePath else null
    }

    private fun openDb(path: String): SQLiteDatabase? = try {
        SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READONLY)
    } catch (_: Exception) {
        null
    }
}
