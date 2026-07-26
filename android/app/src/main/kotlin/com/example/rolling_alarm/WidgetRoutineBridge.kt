package com.example.rolling_alarm

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import es.antonborri.home_widget.HomeWidgetPlugin
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

/**
 * Bridges Drift SQLite routine rows into HomeWidgetPreferences keys that each
 * Glance instance resolves via its own stored [routine_id].
 */
object WidgetRoutineBridge {
    const val PREFS_ROUTINE_ID_KEY = "routine_id"
    private const val DISMISS_ACTION = 0 // LogActionTypeCodeEnum.Dismiss

    private val alarmClockFormat = SimpleDateFormat("hh:mm a", Locale.getDefault())

    data class RoutineChoice(val id: Int, val name: String)

    data class RoutineDisplay(
        val name: String,
        val nextAlarmTime: String,
        val intervalTime: String,
        val dismissalsToday: String,
    )

    fun listActiveRoutines(context: Context): List<RoutineChoice> {
        val dbPath = dbPath(context) ?: return emptyList()
        return openDb(dbPath)?.use { db ->
            db.rawQuery(
                """
                SELECT id, name FROM routines
                WHERE deleted = 0 AND is_active = 1
                ORDER BY created_at ASC
                """.trimIndent(),
                null,
            ).use { cursor ->
                buildList {
                    while (cursor.moveToNext()) {
                        add(RoutineChoice(cursor.getInt(0), cursor.getString(1) ?: "Routine"))
                    }
                }
            }
        } ?: emptyList()
    }

    fun writeRoutineDisplay(context: Context, routineId: Int): RoutineDisplay? {
        val dbPath = dbPath(context) ?: return null
        val display = openDb(dbPath)?.use { db -> loadDisplay(db, routineId) } ?: return null
        persistDisplay(context, routineId, display)
        return display
    }

    fun readDisplay(context: Context, routineId: Int?): RoutineDisplay {
        if (routineId == null || routineId <= 0) {
            return emptyDisplay()
        }
        val prefs = HomeWidgetPlugin.getData(context)
        return RoutineDisplay(
            name = prefs.getString(nameKey(routineId), null) ?: "No Routine",
            nextAlarmTime = prefs.getString(nextAlarmKey(routineId), null) ?: "--:--",
            intervalTime = prefs.getString(intervalKey(routineId), null) ?: "--",
            dismissalsToday = prefs.getString(dismissalsKey(routineId), null) ?: "0",
        )
    }

    fun nameKey(routineId: Int) = "routine_${routineId}_name"
    fun nextAlarmKey(routineId: Int) = "routine_${routineId}_next_alarm_time"
    fun intervalKey(routineId: Int) = "routine_${routineId}_interval_time"
    fun dismissalsKey(routineId: Int) = "routine_${routineId}_dismissals_today"

    private fun emptyDisplay() = RoutineDisplay(
        name = "No Routine",
        nextAlarmTime = "--:--",
        intervalTime = "--",
        dismissalsToday = "0",
    )

    private fun persistDisplay(context: Context, routineId: Int, display: RoutineDisplay) {
        HomeWidgetPlugin.getData(context).edit()
            .putString(nameKey(routineId), display.name)
            .putString(nextAlarmKey(routineId), display.nextAlarmTime)
            .putString(intervalKey(routineId), display.intervalTime)
            .putString(dismissalsKey(routineId), display.dismissalsToday)
            .apply()
    }

    private fun loadDisplay(db: SQLiteDatabase, routineId: Int): RoutineDisplay? {
        val routine = db.rawQuery(
            """
            SELECT name, interval_seconds, day_start_seconds, deleted, is_active
            FROM routines WHERE id = ?
            """.trimIndent(),
            arrayOf(routineId.toString()),
        ).use { cursor ->
            if (!cursor.moveToFirst()) return null
            val deleted = cursor.getInt(3) == 1
            val active = cursor.getInt(4) == 1
            if (deleted || !active) return emptyDisplay()
            Triple(cursor.getString(0) ?: "Routine", cursor.getInt(1), cursor.getInt(2))
        }

        val nextRaw = db.rawQuery(
            """
            SELECT next_trigger_time FROM routine_states
            WHERE routine_id = ? AND deleted = 0
            LIMIT 1
            """.trimIndent(),
            arrayOf(routineId.toString()),
        ).use { cursor ->
            if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) else null
        }

        val periodStart = periodStartMillis(System.currentTimeMillis(), routine.third)
        val dismissals = db.rawQuery(
            """
            SELECT COUNT(*) FROM log_entries
            WHERE deleted = 0
              AND routine_id = ?
              AND log_action_type_code = ?
              AND timestamp >= ?
            """.trimIndent(),
            arrayOf(
                routineId.toString(),
                DISMISS_ACTION.toString(),
                toDriftTimestamp(periodStart).toString(),
            ),
        ).use { cursor ->
            if (cursor.moveToFirst()) cursor.getInt(0) else 0
        }

        val nextAlarm = nextRaw?.let {
            alarmClockFormat.format(Date(fromDriftTimestamp(it)))
        } ?: "--:--"

        return RoutineDisplay(
            name = routine.first,
            nextAlarmTime = nextAlarm,
            intervalTime = formatInterval(routine.second),
            dismissalsToday = dismissals.toString(),
        )
    }

    private fun formatInterval(totalSeconds: Int): String {
        if (totalSeconds <= 0) return "0s"
        val h = totalSeconds / 3600
        val m = (totalSeconds % 3600) / 60
        val s = totalSeconds % 60
        val parts = mutableListOf<String>()
        if (h > 0) parts.add("${h}h")
        if (m > 0) parts.add("${m}m")
        if (s > 0 || parts.isEmpty()) parts.add("${s}s")
        return parts.joinToString(" ")
    }

    /** Drift DateTime columns are stored as microseconds since epoch. */
    private fun fromDriftTimestamp(raw: Long): Long = when {
        raw > 100_000_000_000_000L -> raw / 1000L
        raw > 100_000_000_000L -> raw
        else -> raw * 1000L
    }

    private fun toDriftTimestamp(epochMillis: Long): Long = epochMillis * 1000L

    private fun periodStartMillis(nowMillis: Long, dayStartSeconds: Int): Long {
        val offsetSec = dayStartSeconds.coerceIn(0, 24 * 3600 - 1)
        val cal = Calendar.getInstance().apply { timeInMillis = nowMillis }
        val todayStart = Calendar.getInstance().apply {
            timeInMillis = nowMillis
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            add(Calendar.SECOND, offsetSec)
        }
        return if (cal.before(todayStart)) {
            todayStart.timeInMillis - TimeUnit.DAYS.toMillis(1)
        } else {
            todayStart.timeInMillis
        }
    }

    private fun dbPath(context: Context): String? {
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE,
        )
        return prefs.getString("flutter.ra_db_path", null)
            ?: prefs.getString("ra_db_path", null)
    }

    private fun openDb(path: String): SQLiteDatabase? = try {
        SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READONLY)
    } catch (_: Exception) {
        null
    }
}
