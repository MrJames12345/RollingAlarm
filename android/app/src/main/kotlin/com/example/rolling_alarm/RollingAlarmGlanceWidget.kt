package com.example.rolling_alarm

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.glance.text.FontFamily
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import es.antonborri.home_widget.actionStartActivity

/**
 * Read-only home screen dashboard for one user-selected routine per widget instance.
 * [routine_id] lives in per-instance Glance preferences; display strings are bridged
 * via HomeWidgetPreferences keys scoped by that id.
 */
class RollingAlarmGlanceWidget : GlanceAppWidget() {

    override val stateDefinition = PreferencesGlanceStateDefinition

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            val prefs = currentState<Preferences>()
            val routineId = prefs[intPreferencesKey(WidgetRoutineBridge.PREFS_ROUTINE_ID_KEY)]
            GlanceContent(context, routineId)
        }
    }

    @Composable
    private fun GlanceContent(context: Context, routineId: Int?) {
        val display = WidgetRoutineBridge.readDisplay(context, routineId)

        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(ColorProvider(OffBlack))
                .padding(16.dp)
                .clickable(onClick = actionStartActivity<MainActivity>(context)),
            verticalAlignment = Alignment.Vertical.Top,
            horizontalAlignment = Alignment.Horizontal.Start,
        ) {
            Text(
                text = display.name,
                style = TextStyle(
                    color = ColorProvider(Primary),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                ),
                maxLines = 1,
            )

            Spacer(modifier = GlanceModifier.height(8.dp))

            Text(
                text = display.nextAlarmTime,
                style = TextStyle(
                    color = ColorProvider(Teal),
                    fontSize = 28.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace,
                ),
                maxLines = 1,
            )

            Spacer(modifier = GlanceModifier.height(12.dp))

            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.Vertical.CenterVertically,
            ) {
                MetricColumn(
                    label = "Interval",
                    value = display.intervalTime,
                    valueColor = Teal,
                )
                Spacer(modifier = GlanceModifier.width(24.dp))
                MetricColumn(
                    label = "Dismissed",
                    value = display.dismissalsToday,
                    valueColor = SoftCoral,
                )
            }
        }
    }

    @Composable
    private fun MetricColumn(
        label: String,
        value: String,
        valueColor: Color,
    ) {
        Column {
            Text(
                text = label,
                style = TextStyle(
                    color = ColorProvider(MutedPrimary),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Normal,
                ),
                maxLines = 1,
            )
            Spacer(modifier = GlanceModifier.height(2.dp))
            Text(
                text = value,
                style = TextStyle(
                    color = ColorProvider(valueColor),
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace,
                ),
                maxLines = 1,
            )
        }
    }

    companion object {
        private val OffBlack = Color(0xFF0A0A0A)
        private val Primary = Color(0xFFD4D2CF)
        private val MutedPrimary = Color(0x80D4D2CF)
        private val Teal = Color(0xFF6B9A92)
        private val SoftCoral = Color(0xFFC17F74)
    }
}
