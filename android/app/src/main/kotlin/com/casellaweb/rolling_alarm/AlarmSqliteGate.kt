package com.casellaweb.rolling_alarm

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteException
import java.io.File
import java.util.Calendar
import java.util.TimeZone

/**
 * Read-only SQLite guard against Drift's `rolling_alarm.db`.
 *
 * Prevents native [AlarmRingingService] / [AlarmReceiver] / [AlarmResurrectionReceiver]
 * from waking the screen or playing audio for routines that were muted, paused,
 * soft-deleted, on a disabled weekday, on an R&R off-swing day, or already at
 * their daily cap before a pending `setAlarmClock` fired.
 */
object AlarmSqliteGate {
    private const val ALL_DAYS_MASK = 0x7F
    private const val MILLIS_PER_DAY = 86_400_000L

    private data class RoutineGateRow(
        val deleted: Boolean,
        val isActive: Boolean,
        val enabledWeekdays: Int,
        val dayStartSeconds: Int,
        val maxTimesPerDayEnabled: Boolean,
        val maxTimesPerDay: Int,
        val cycleOnDays: Int,
        val cycleOffDays: Int,
        val cycleAnchorEpochDay: Int?,
    )

    private data class StateGateRow(
        val deleted: Boolean,
        val isMuted: Boolean,
        val currentSnoozeCount: Int,
        val timesRingToday: Int,
        val timesRingDayRaw: Long?,
        val extraMaxTimesToday: Int,
    )

    /**
     * Returns `true` when [routineId] must NOT ring natively right now:
     * - routine row is missing
     * - `routines.deleted == 1` or `routines.is_active == 0`
     * - `routine_states.deleted == 1` or `routine_states.muted_at != null`
     * - fresh cycle (`current_snooze_count == 0`) on a disabled weekday
     * - fresh cycle (`current_snooze_count == 0`) whose daily cap is already reached
     *
     * Snooze resumes (`current_snooze_count > 0`) bypass weekday and daily-cap
     * checks so an in-progress cycle can always finish.
     *
     * Fails open (`false`) if the database file cannot be resolved or opened so
     * transient storage errors never silence a real alarm.
     */
    fun shouldSuppressRing(context: Context, routineId: Int): Boolean {
        return evaluateGate(context, routineId, checkScheduleWindowNow = true)
    }

    /**
     * Returns `true` when [routineId] should NOT be re-armed on boot/update:
     * only checks structural eligibility (missing, deleted, inactive, muted) so
     * valid future alarms parked for tomorrow's day-start or an upcoming enabled
     * weekday are never discarded at boot.
     */
    fun shouldSuppressResurrection(context: Context, routineId: Int): Boolean {
        return evaluateGate(context, routineId, checkScheduleWindowNow = false)
    }

    private fun evaluateGate(
        context: Context,
        routineId: Int,
        checkScheduleWindowNow: Boolean,
    ): Boolean {
        if (routineId < 0) return true
        val path = dbPath(context) ?: return false
        val db = openDb(path) ?: return false
        return try {
            db.use { sqlite ->
                val routineRow = queryRoutineGateRow(sqlite, routineId) ?: return true

                if (routineRow.deleted || !routineRow.isActive) {
                    return true
                }

                val stateRow = sqlite.rawQuery(
                    """
                    SELECT deleted, muted_at, current_snooze_count,
                           times_ring_today, times_ring_day, extra_max_times_today
                    FROM routine_states
                    WHERE routine_id = ?
                    LIMIT 1
                    """.trimIndent(),
                    arrayOf(routineId.toString()),
                ).use { cursor ->
                    if (!cursor.moveToFirst()) null
                    else StateGateRow(
                        deleted = cursor.getInt(0) == 1,
                        isMuted = !cursor.isNull(1),
                        currentSnoozeCount = cursor.getInt(2),
                        timesRingToday = cursor.getInt(3),
                        timesRingDayRaw = if (cursor.isNull(4)) null else cursor.getLong(4),
                        extraMaxTimesToday = cursor.getInt(5),
                    )
                } ?: return false

                if (stateRow.deleted || stateRow.isMuted) {
                    return true
                }

                if (!checkScheduleWindowNow) {
                    return false
                }

                // Snooze resumes always ring so an active alarm cycle can finish.
                val isFreshCycle = stateRow.currentSnoozeCount == 0
                if (!isFreshCycle) {
                    return false
                }

                val nowMillis = System.currentTimeMillis()
                val swingAnchor = routineRow.cycleAnchorEpochDay
                if (routineRow.cycleOnDays > 0 &&
                    routineRow.cycleOffDays > 0 &&
                    swingAnchor != null
                ) {
                    val logicalPeriodCal = periodStartCalendar(nowMillis, routineRow.dayStartSeconds)
                    if (!isOnSwingDay(
                            logicalPeriodCal = logicalPeriodCal,
                            cycleOnDays = routineRow.cycleOnDays,
                            cycleOffDays = routineRow.cycleOffDays,
                            cycleAnchorEpochDay = swingAnchor,
                        )
                    ) {
                        return true
                    }
                    if (!isWeekdayEnabled(routineRow.enabledWeekdays, logicalPeriodCal.timeInMillis)) {
                        return true
                    }
                } else {
                    if (!isWeekdayEnabled(routineRow.enabledWeekdays, nowMillis)) {
                        return true
                    }
                }

                if (routineRow.maxTimesPerDayEnabled && routineRow.maxTimesPerDay > 0) {
                    val currentPeriod = periodStartMillis(nowMillis, routineRow.dayStartSeconds)
                    val storedDayMillis = stateRow.timesRingDayRaw?.let { fromDriftTimestamp(it) }
                    val samePeriod = storedDayMillis != null &&
                        periodStartMillis(storedDayMillis, routineRow.dayStartSeconds) == currentPeriod
                    val effectiveCount = if (samePeriod) stateRow.timesRingToday else 0
                    val effectiveExtra = if (samePeriod) stateRow.extraMaxTimesToday else 0
                    val effectiveCap = (routineRow.maxTimesPerDay + effectiveExtra).coerceIn(0, 999)
                    if (effectiveCount >= effectiveCap) {
                        return true
                    }
                }

                false
            }
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Reads v19 routine columns including swing-roster metadata, falling back
     * to v18 columns cleanly if an alarm fires after app update before Drift
     * has run its v18 -> v19 migration.
     */
    private fun queryRoutineGateRow(sqlite: SQLiteDatabase, routineId: Int): RoutineGateRow? {
        return try {
            sqlite.rawQuery(
                """
                SELECT deleted, is_active, enabled_weekdays, day_start_seconds,
                       max_times_per_day_enabled, max_times_per_day,
                       cycle_on_days, cycle_off_days, cycle_anchor_epoch_day
                FROM routines
                WHERE id = ?
                LIMIT 1
                """.trimIndent(),
                arrayOf(routineId.toString()),
            ).use { cursor ->
                if (!cursor.moveToFirst()) return null
                RoutineGateRow(
                    deleted = cursor.getInt(0) == 1,
                    isActive = cursor.getInt(1) == 1,
                    enabledWeekdays = cursor.getInt(2),
                    dayStartSeconds = cursor.getInt(3),
                    maxTimesPerDayEnabled = cursor.getInt(4) == 1,
                    maxTimesPerDay = cursor.getInt(5),
                    cycleOnDays = cursor.getInt(6),
                    cycleOffDays = cursor.getInt(7),
                    cycleAnchorEpochDay = if (cursor.isNull(8)) null else cursor.getInt(8),
                )
            }
        } catch (_: SQLiteException) {
            sqlite.rawQuery(
                """
                SELECT deleted, is_active, enabled_weekdays, day_start_seconds,
                       max_times_per_day_enabled, max_times_per_day
                FROM routines
                WHERE id = ?
                LIMIT 1
                """.trimIndent(),
                arrayOf(routineId.toString()),
            ).use { cursor ->
                if (!cursor.moveToFirst()) return null
                RoutineGateRow(
                    deleted = cursor.getInt(0) == 1,
                    isActive = cursor.getInt(1) == 1,
                    enabledWeekdays = cursor.getInt(2),
                    dayStartSeconds = cursor.getInt(3),
                    maxTimesPerDayEnabled = cursor.getInt(4) == 1,
                    maxTimesPerDay = cursor.getInt(5),
                    cycleOnDays = 0,
                    cycleOffDays = 0,
                    cycleAnchorEpochDay = null,
                )
            }
        }
    }

    /**
     * Matches Dart `RA_SwingRosterSchedule.isEpochDayOnSwing`: projects the
     * logical period's local calendar `(year, month, day)` onto UTC midnight
     * for DST-safe epoch-day indexing and applies Euclidean modulo.
     */
    private fun isOnSwingDay(
        logicalPeriodCal: Calendar,
        cycleOnDays: Int,
        cycleOffDays: Int,
        cycleAnchorEpochDay: Int,
    ): Boolean {
        val utcCal = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
            clear()
            set(
                logicalPeriodCal.get(Calendar.YEAR),
                logicalPeriodCal.get(Calendar.MONTH),
                logicalPeriodCal.get(Calendar.DAY_OF_MONTH),
                0,
                0,
                0,
            )
            set(Calendar.MILLISECOND, 0)
        }
        val logicalEpochDay = Math.floorDiv(utcCal.timeInMillis, MILLIS_PER_DAY).toInt()
        val cycleLength = cycleOnDays + cycleOffDays
        val delta = logicalEpochDay - cycleAnchorEpochDay
        val pos = ((delta % cycleLength) + cycleLength) % cycleLength
        return pos < cycleOnDays
    }

    /** Matches Dart `RA_WeekdaySchedule`: bit 0 = Monday .. bit 6 = Sunday; 0 = all days. */
    private fun isWeekdayEnabled(mask: Int, nowMillis: Long): Boolean {
        val effective = if (mask == 0) ALL_DAYS_MASK else (mask and ALL_DAYS_MASK)
        if (effective == ALL_DAYS_MASK) return true
        val cal = Calendar.getInstance().apply { timeInMillis = nowMillis }
        val bitIndex = when (cal.get(Calendar.DAY_OF_WEEK)) {
            Calendar.MONDAY -> 0
            Calendar.TUESDAY -> 1
            Calendar.WEDNESDAY -> 2
            Calendar.THURSDAY -> 3
            Calendar.FRIDAY -> 4
            Calendar.SATURDAY -> 5
            Calendar.SUNDAY -> 6
            else -> return true
        }
        return (effective and (1 shl bitIndex)) != 0
    }

    /** Local DST-safe day-start boundary matching Dart `RA_DailyRingLimit.periodStart`. */
    private fun periodStartCalendar(nowMillis: Long, dayStartSeconds: Int): Calendar {
        val offsetSec = dayStartSeconds.coerceIn(0, 24 * 3600 - 1)
        val hour = offsetSec / 3600
        val minute = (offsetSec % 3600) / 60
        val second = offsetSec % 60
        val cal = Calendar.getInstance().apply { timeInMillis = nowMillis }
        val todayStart = Calendar.getInstance().apply {
            timeInMillis = nowMillis
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, second)
            set(Calendar.MILLISECOND, 0)
        }
        if (cal.before(todayStart)) {
            todayStart.add(Calendar.DAY_OF_MONTH, -1)
            todayStart.set(Calendar.HOUR_OF_DAY, hour)
            todayStart.set(Calendar.MINUTE, minute)
            todayStart.set(Calendar.SECOND, second)
            todayStart.set(Calendar.MILLISECOND, 0)
        }
        return todayStart
    }

    private fun periodStartMillis(nowMillis: Long, dayStartSeconds: Int): Long {
        return periodStartCalendar(nowMillis, dayStartSeconds).timeInMillis
    }

    /** Drift DateTime columns are stored as Unix seconds (defensively decode ms/us too). */
    private fun fromDriftTimestamp(raw: Long): Long = when {
        raw > 100_000_000_000_000L -> raw / 1000L
        raw > 100_000_000_000L -> raw
        else -> raw * 1000L
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
        SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READONLY).also { db ->
            try {
                db.rawQuery("PRAGMA busy_timeout = 5000", null).use { it.moveToFirst() }
            } catch (_: Exception) {
            }
        }
    } catch (_: Exception) {
        null
    }
}
