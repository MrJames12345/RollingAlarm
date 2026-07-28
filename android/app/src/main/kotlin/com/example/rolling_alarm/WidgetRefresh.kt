package com.example.rolling_alarm

import android.content.Context
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.state.getAppWidgetState
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.state.PreferencesGlanceStateDefinition
import kotlinx.coroutines.runBlocking

/**
 * Forces every Rolling Alarm Glance instance to re-read SQLite and redraw.
 *
 * [HomeWidget.updateWidget] only broadcasts [android.appwidget.AppWidgetManager.ACTION_APPWIDGET_UPDATE].
 * With [PreferencesGlanceStateDefinition], Glance can keep showing the prior
 * composition when preferences (routine_id) did not change after snooze/dismiss.
 * Bumping [REFRESH_AT_KEY] invalidates that cache so next-alarm / dismissals
 * always refresh on the home screen.
 */
object WidgetRefresh {
    private val REFRESH_AT_KEY = longPreferencesKey("ra_widget_refresh_at")

    fun refreshAll(context: Context) {
        runBlocking {
            val appContext = context.applicationContext
            val manager = GlanceAppWidgetManager(appContext)
            val widget = RollingAlarmGlanceWidget()
            val ids = try {
                manager.getGlanceIds(RollingAlarmGlanceWidget::class.java)
            } catch (_: Exception) {
                emptyList()
            }
            for (glanceId in ids) {
                try {
                    updateAppWidgetState(
                        appContext,
                        PreferencesGlanceStateDefinition,
                        glanceId,
                    ) { prefs ->
                        prefs.toMutablePreferences().apply {
                            this[REFRESH_AT_KEY] = System.currentTimeMillis()
                        }
                    }
                    val state = getAppWidgetState(
                        appContext,
                        PreferencesGlanceStateDefinition,
                        glanceId,
                    )
                    val routineId =
                        state[intPreferencesKey(WidgetRoutineBridge.PREFS_ROUTINE_ID_KEY)]
                    if (routineId != null && routineId > 0) {
                        WidgetRoutineBridge.writeRoutineDisplay(appContext, routineId)
                    }
                    widget.update(appContext, glanceId)
                } catch (_: Exception) {
                    // One bad instance must not block the rest.
                }
            }
        }
    }
}
