package com.example.rolling_alarm

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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
import androidx.glance.text.FontFamily
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.actionStartActivity

/**
 * Read-only home screen dashboard for the single user-pinned Rolling Alarm routine.
 * Data is bridged from Flutter via home_widget SharedPreferences keys.
 */
class RollingAlarmGlanceWidget : GlanceAppWidget() {

    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            GlanceContent(context, currentState())
        }
    }

    @Composable
    private fun GlanceContent(context: Context, currentState: HomeWidgetGlanceState) {
        val prefs = currentState.preferences
        val routineName = prefs.getString("routine_name", "No Routine") ?: "No Routine"
        val nextAlarmTime = prefs.getString("next_alarm_time", "--:--") ?: "--:--"
        val intervalTime = prefs.getString("interval_time", "--") ?: "--"
        val dismissalsToday = prefs.getString("dismissals_today", "0") ?: "0"

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
                text = routineName,
                style = TextStyle(
                    color = ColorProvider(Primary),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                ),
                maxLines = 1,
            )

            Spacer(modifier = GlanceModifier.height(8.dp))

            Text(
                text = nextAlarmTime,
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
                    value = intervalTime,
                    valueColor = Teal,
                )
                Spacer(modifier = GlanceModifier.width(24.dp))
                MetricColumn(
                    label = "Dismissed",
                    value = dismissalsToday,
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
        // Matches lib/styles.dart RA_ColourStyles
        private val OffBlack = Color(0xFF0A0A0A)
        private val Primary = Color(0xFFD4D2CF)
        private val MutedPrimary = Color(0x80D4D2CF)
        private val Teal = Color(0xFF6B9A92)
        private val SoftCoral = Color(0xFFC17F74)
    }
}
