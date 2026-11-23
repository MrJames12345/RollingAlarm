package com.casellaweb.rolling_alarm

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.state.getAppWidgetState
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.state.PreferencesGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetPlugin
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

        if (!isProUser() && countOtherConfiguredWidgets() >= FREE_WIDGET_LIMIT) {
            setContentView(buildProGateUi())
            return
        }

        val routines = WidgetRoutineBridge.listActiveRoutines(this)
        setContentView(buildUi(routines))
    }

    private fun isProUser(): Boolean {
        val flutterPrefs = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        if (flutterPrefs.contains(FLUTTER_IS_PRO_EFFECTIVE_KEY)) {
            return flutterPrefs.getBoolean(FLUTTER_IS_PRO_EFFECTIVE_KEY, false)
        }
        val homeWidgetPrefs = HomeWidgetPlugin.getData(this)
        if (homeWidgetPrefs.contains(WIDGET_IS_PRO_KEY)) {
            return homeWidgetPrefs.getBoolean(WIDGET_IS_PRO_KEY, false)
        }
        if (flutterPrefs.contains(FLUTTER_IS_PRO_FALLBACK_KEY)) {
            return flutterPrefs.getBoolean(FLUTTER_IS_PRO_FALLBACK_KEY, false)
        }
        return flutterPrefs.getBoolean(FLUTTER_RC_CACHED_KEY, false)
    }

    /**
     * Counts other already-configured Rolling Alarm Glance widgets on the launcher,
     * excluding the [appWidgetId] currently being added or reconfigured.
     */
    private fun countOtherConfiguredWidgets(): Int {
        return runBlocking {
            try {
                val manager = GlanceAppWidgetManager(this@WidgetConfigActivity)
                val currentGlanceId = try {
                    manager.getGlanceIdBy(appWidgetId)
                } catch (_: Exception) {
                    null
                }
                val allIds = manager.getGlanceIds(RollingAlarmGlanceWidget::class.java)
                var count = 0
                for (glanceId in allIds) {
                    if (currentGlanceId != null && glanceId == currentGlanceId) continue
                    val state = try {
                        getAppWidgetState(
                            this@WidgetConfigActivity,
                            PreferencesGlanceStateDefinition,
                            glanceId,
                        )
                    } catch (_: Exception) {
                        null
                    }
                    val routineId =
                        state?.get(intPreferencesKey(WidgetRoutineBridge.PREFS_ROUTINE_ID_KEY))
                    if (routineId != null && routineId > 0) {
                        count++
                    }
                }
                count
            } catch (_: Exception) {
                0
            }
        }
    }

    private fun buildProGateUi(): View {
        val density = resources.displayMetrics.density
        fun dp(value: Int) = (value * density).toInt()

        val scroll = ScrollView(this).apply {
            isFillViewport = true
            fitsSystemWindows = true
            setBackgroundColor(COLOR_OFF_BLACK)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(COLOR_OFF_BLACK)
            setPaddingRelative(dp(24), dp(32), dp(24), dp(32))
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
        }

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply {
                setColor(COLOR_SURFACE)
                cornerRadius = dp(16).toFloat()
                setStroke(maxOf(1, dp(1)), COLOR_CORAL)
            }
            setPaddingRelative(dp(20), dp(24), dp(20), dp(24))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
        }

        card.addView(
            TextView(this).apply {
                text = getString(R.string.widget_pro_title)
                setTextColor(COLOR_CORAL)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
                typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
                textAlignment = View.TEXT_ALIGNMENT_VIEW_START
                gravity = Gravity.START
            },
        )

        card.addView(
            TextView(this).apply {
                text = getString(R.string.widget_pro_message)
                setTextColor(COLOR_PRIMARY)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                setPaddingRelative(0, dp(12), 0, dp(24))
                textAlignment = View.TEXT_ALIGNMENT_VIEW_START
                gravity = Gravity.START
            },
        )

        card.addView(
            TextView(this).apply {
                text = getString(R.string.widget_pro_unlock)
                setTextColor(COLOR_ON_ACCENT)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
                gravity = Gravity.CENTER
                background = GradientDrawable().apply {
                    setColor(COLOR_CORAL)
                    cornerRadius = dp(14).toFloat()
                }
                setPaddingRelative(dp(16), dp(14), dp(16), dp(14))
                isClickable = true
                isFocusable = true
                setOnClickListener { openPaywallInApp() }
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ).apply {
                    bottomMargin = dp(10)
                }
            },
        )

        card.addView(
            TextView(this).apply {
                text = getString(R.string.widget_pro_cancel)
                setTextColor(COLOR_MUTED)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                gravity = Gravity.CENTER
                setPaddingRelative(dp(16), dp(12), dp(16), dp(12))
                isClickable = true
                isFocusable = true
                setOnClickListener {
                    setResult(RESULT_CANCELED)
                    finish()
                }
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                )
            },
        )

        root.addView(card)
        scroll.addView(root)
        return scroll
    }

    private fun openPaywallInApp() {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
            putExtra(MainActivity.EXTRA_OPEN_PAYWALL, true)
            putExtra(
                MainActivity.EXTRA_PAYWALL_TRIGGER,
                "Unlock unlimited home screen routine widgets with Pro",
            )
        }
        startActivity(launchIntent)
        setResult(RESULT_CANCELED)
        finish()
    }

    private fun buildUi(routines: List<WidgetRoutineBridge.RoutineChoice>): View {
        val density = resources.displayMetrics.density
        fun dp(value: Int) = (value * density).toInt()

        // Keep fitsSystemWindows on the outer wrapper so Android's system-bar
        // inset padding does not overwrite the inner container's content padding.
        val container = FrameLayout(this).apply {
            fitsSystemWindows = true
            setBackgroundColor(COLOR_OFF_BLACK)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(COLOR_OFF_BLACK)
            setPaddingRelative(dp(20), dp(28), dp(20), dp(20))
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }
        container.addView(root)

        root.addView(
            TextView(this).apply {
                text = getString(R.string.widget_config_title)
                setTextColor(COLOR_PRIMARY)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
                typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
                textAlignment = View.TEXT_ALIGNMENT_VIEW_START
                gravity = Gravity.START
            },
        )
        root.addView(
            TextView(this).apply {
                text = getString(R.string.widget_config_subtitle)
                setTextColor(COLOR_MUTED)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                setPaddingRelative(0, dp(8), 0, dp(20))
                textAlignment = View.TEXT_ALIGNMENT_VIEW_START
                gravity = Gravity.START
            },
        )

        if (routines.isEmpty()) {
            root.addView(
                TextView(this).apply {
                    text = getString(R.string.widget_config_empty)
                    setTextColor(COLOR_CORAL)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                    textAlignment = View.TEXT_ALIGNMENT_VIEW_START
                    gravity = Gravity.START
                },
            )
            return container
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
                    setPaddingRelative(dp(16), dp(18), dp(16), dp(18))
                    textAlignment = View.TEXT_ALIGNMENT_VIEW_START
                    gravity = Gravity.START or Gravity.CENTER_VERTICAL
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
        return container
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
        private const val FREE_WIDGET_LIMIT = 1
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val FLUTTER_IS_PRO_EFFECTIVE_KEY = "flutter.ra_is_pro_effective"
        private const val FLUTTER_IS_PRO_FALLBACK_KEY = "flutter.ra_is_pro"
        private const val FLUTTER_RC_CACHED_KEY = "flutter.ra_rc_is_pro_cached"
        private const val WIDGET_IS_PRO_KEY = "ra_is_pro"
        private const val COLOR_OFF_BLACK = 0xFF0A0A0A.toInt()
        private const val COLOR_SURFACE = 0xFF161616.toInt()
        private const val COLOR_PRIMARY = 0xFFD4D2CF.toInt()
        private const val COLOR_MUTED = 0x80D4D2CF.toInt()
        private const val COLOR_CORAL = 0xFFC17F74.toInt()
        private const val COLOR_ON_ACCENT = 0xFF0A0A0A.toInt()
    }
}
