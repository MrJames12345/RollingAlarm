package com.example.rolling_alarm

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.graphics.Typeface
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.state.updateAppWidgetState
import kotlinx.coroutines.runBlocking

/**
 * Launched by the launcher when the user adds (or reconfigures) a Rolling Alarm
 * widget. Picks which routine that widget instance should display.
 */
class WidgetConfigActivity : Activity() {
    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)

        appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        val routines = WidgetRoutineBridge.listActiveRoutines(this)
        setContentView(buildUi(routines))
    }

    private fun buildUi(routines: List<WidgetRoutineBridge.RoutineChoice>): View {
        val density = resources.displayMetrics.density
        fun dp(value: Int) = (value * density).toInt()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(COLOR_OFF_BLACK)
            setPadding(dp(20), dp(28), dp(20), dp(20))
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }

        root.addView(
            TextView(this).apply {
                text = "Choose a routine"
                setTextColor(COLOR_PRIMARY)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
                typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
            },
        )
        root.addView(
            TextView(this).apply {
                text = "This home screen widget will show the selected routine."
                setTextColor(COLOR_MUTED)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                setPadding(0, dp(8), 0, dp(20))
            },
        )

        if (routines.isEmpty()) {
            root.addView(
                TextView(this).apply {
                    text = "No active routines yet. Create one in Rolling Alarm, then try again."
                    setTextColor(COLOR_CORAL)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                },
            )
            return root
        }

        val list = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }

        routines.forEach { routine ->
            list.addView(
                TextView(this).apply {
                    text = routine.name
                    setTextColor(COLOR_PRIMARY)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                    typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
                    setBackgroundColor(COLOR_SURFACE)
                    setPadding(dp(16), dp(18), dp(16), dp(18))
                    gravity = Gravity.CENTER_VERTICAL
                    isClickable = true
                    isFocusable = true
                    setOnClickListener { confirmRoutine(routine.id) }
                    val lp = LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                    )
                    lp.bottomMargin = dp(10)
                    layoutParams = lp
                },
            )
        }

        val scroll = ScrollView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f,
            )
            addView(list)
        }
        root.addView(scroll)
        return root
    }

    private fun confirmRoutine(routineId: Int) {
        WidgetRoutineBridge.writeRoutineDisplay(this, routineId)

        runBlocking {
            val glanceId = GlanceAppWidgetManager(this@WidgetConfigActivity)
                .getGlanceIdBy(appWidgetId)
            updateAppWidgetState(this@WidgetConfigActivity, glanceId) { prefs ->
                prefs[intPreferencesKey(WidgetRoutineBridge.PREFS_ROUTINE_ID_KEY)] = routineId
            }
            RollingAlarmGlanceWidget().update(this@WidgetConfigActivity, glanceId)
        }

        val result = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        setResult(RESULT_OK, result)
        finish()
    }

    companion object {
        private const val COLOR_OFF_BLACK = 0xFF0A0A0A.toInt()
        private const val COLOR_SURFACE = 0xFF161616.toInt()
        private const val COLOR_PRIMARY = 0xFFD4D2CF.toInt()
        private const val COLOR_MUTED = 0x80D4D2CF.toInt()
        private const val COLOR_CORAL = 0xFFC17F74.toInt()
    }
}
