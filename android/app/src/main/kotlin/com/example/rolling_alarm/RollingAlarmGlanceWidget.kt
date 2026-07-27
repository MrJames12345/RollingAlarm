package com.example.rolling_alarm

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.state.getAppWidgetState
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.glance.text.FontFamily
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import es.antonborri.home_widget.actionStartActivity

/**
 * Responsive home screen dashboard for one user-selected routine per widget instance.
 *
 * [SizeMode.Responsive] serves Small (2x1), Medium (4x2), and Large (4x3) layouts.
 * [routine_id] lives in per-instance Glance preferences; display strings are bridged
 * via HomeWidgetPreferences keys scoped by that id.
 */
class RollingAlarmGlanceWidget : GlanceAppWidget() {

    override val stateDefinition = PreferencesGlanceStateDefinition

    override val sizeMode = SizeMode.Responsive(
        setOf(SMALL_SIZE, MEDIUM_SIZE, LARGE_SIZE),
    )

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        // Re-read SQLite on every redraw (snooze / dismiss / schedule) so the
        // home screen is not stuck on HomeWidgetPreferences written earlier.
        val glanceState = getAppWidgetState(context, PreferencesGlanceStateDefinition, id)
        val routineId = glanceState[intPreferencesKey(WidgetRoutineBridge.PREFS_ROUTINE_ID_KEY)]
        val freshDisplay = if (routineId != null && routineId > 0) {
            WidgetRoutineBridge.writeRoutineDisplay(context, routineId)
        } else {
            null
        }

        provideContent {
            val prefs = currentState<Preferences>()
            val pinnedRoutineId =
                prefs[intPreferencesKey(WidgetRoutineBridge.PREFS_ROUTINE_ID_KEY)]
            val display = freshDisplay
                ?: WidgetRoutineBridge.readDisplay(context, pinnedRoutineId)
            val size = LocalSize.current

            Box(
                modifier = GlanceModifier
                    .fillMaxSize()
                    .background(ColorProvider(OledBlack))
                    .cornerRadius(16.dp)
                    .padding(8.dp)
                    .clickable(onClick = actionStartActivity<MainActivity>(context)),
            ) {
                when {
                    size.height >= LARGE_SIZE.height && size.width >= LARGE_SIZE.width ->
                        LargeWidgetUI(display)
                    size.width >= MEDIUM_SIZE.width ->
                        MediumWidgetUI(display)
                    else ->
                        SmallWidgetUI(display)
                }
            }
        }
    }

    // --------------------------------------------------------------------- //
    // Size layouts
    // --------------------------------------------------------------------- //

    /** 2x1: centered title + next alarm time only. */
    @Composable
    private fun SmallWidgetUI(display: WidgetRoutineBridge.RoutineDisplay) {
        Column(
            modifier = GlanceModifier.fillMaxSize(),
            verticalAlignment = Alignment.Vertical.CenterVertically,
            horizontalAlignment = Alignment.Horizontal.CenterHorizontally,
        ) {
            Text(
                text = display.name,
                style = TextStyle(
                    color = ColorProvider(Color.White),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    textAlign = TextAlign.Center,
                ),
                maxLines = 1,
            )
            Spacer(modifier = GlanceModifier.height(4.dp))
            Text(
                text = display.nextAlarmTime,
                style = TextStyle(
                    color = ColorProvider(SurgicalTeal),
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace,
                    textAlign = TextAlign.Center,
                ),
                maxLines = 1,
            )
        }
    }

    /** 4x2: hero card on top; Interval + Dismissed cards below. */
    @Composable
    private fun MediumWidgetUI(display: WidgetRoutineBridge.RoutineDisplay) {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            CardSurface(modifier = GlanceModifier.fillMaxWidth().defaultWeight()) {
                Column(
                    modifier = GlanceModifier.fillMaxSize(),
                    verticalAlignment = Alignment.Vertical.CenterVertically,
                    horizontalAlignment = Alignment.Horizontal.Start,
                ) {
                    Text(
                        text = display.name,
                        style = TextStyle(
                            color = ColorProvider(Color.White),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                        maxLines = 1,
                    )
                    Spacer(modifier = GlanceModifier.height(4.dp))
                    Text(
                        text = display.nextAlarmTime,
                        style = TextStyle(
                            color = ColorProvider(SurgicalTeal),
                            fontSize = 24.sp,
                            fontWeight = FontWeight.Bold,
                            fontFamily = FontFamily.Monospace,
                        ),
                        maxLines = 1,
                    )
                }
            }

            Spacer(modifier = GlanceModifier.height(8.dp))

            Row(
                modifier = GlanceModifier.fillMaxWidth().defaultWeight(),
                verticalAlignment = Alignment.Vertical.CenterVertically,
            ) {
                MetricCard(
                    label = "Interval",
                    value = display.intervalTime,
                    valueColor = SurgicalTeal,
                    modifier = GlanceModifier.defaultWeight().fillMaxHeight(),
                )
                Spacer(modifier = GlanceModifier.width(8.dp))
                MetricCard(
                    label = "Dismissed",
                    value = display.dismissalsToday,
                    valueColor = SoftCoral,
                    modifier = GlanceModifier.defaultWeight().fillMaxHeight(),
                )
            }
        }
    }

    /** 4x3: Medium stack plus Current Phase and Edit/Open App cards. */
    @Composable
    private fun LargeWidgetUI(display: WidgetRoutineBridge.RoutineDisplay) {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            CardSurface(modifier = GlanceModifier.fillMaxWidth().defaultWeight()) {
                Column(
                    modifier = GlanceModifier.fillMaxSize(),
                    verticalAlignment = Alignment.Vertical.CenterVertically,
                    horizontalAlignment = Alignment.Horizontal.Start,
                ) {
                    Text(
                        text = display.name,
                        style = TextStyle(
                            color = ColorProvider(Color.White),
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                        maxLines = 1,
                    )
                    Spacer(modifier = GlanceModifier.height(4.dp))
                    Text(
                        text = display.nextAlarmTime,
                        style = TextStyle(
                            color = ColorProvider(SurgicalTeal),
                            fontSize = 28.sp,
                            fontWeight = FontWeight.Bold,
                            fontFamily = FontFamily.Monospace,
                        ),
                        maxLines = 1,
                    )
                }
            }

            Spacer(modifier = GlanceModifier.height(8.dp))

            Row(
                modifier = GlanceModifier.fillMaxWidth().defaultWeight(),
                verticalAlignment = Alignment.Vertical.CenterVertically,
            ) {
                MetricCard(
                    label = "Interval",
                    value = display.intervalTime,
                    valueColor = SurgicalTeal,
                    modifier = GlanceModifier.defaultWeight().fillMaxHeight(),
                )
                Spacer(modifier = GlanceModifier.width(8.dp))
                MetricCard(
                    label = "Dismissed",
                    value = display.dismissalsToday,
                    valueColor = SoftCoral,
                    modifier = GlanceModifier.defaultWeight().fillMaxHeight(),
                )
            }

            Spacer(modifier = GlanceModifier.height(8.dp))

            Row(
                modifier = GlanceModifier.fillMaxWidth().defaultWeight(),
                verticalAlignment = Alignment.Vertical.CenterVertically,
            ) {
                MetricCard(
                    label = "Current Phase",
                    value = "Active",
                    valueColor = SurgicalTeal,
                    modifier = GlanceModifier.defaultWeight().fillMaxHeight(),
                )
                Spacer(modifier = GlanceModifier.width(8.dp))
                MetricCard(
                    label = "Edit / Open App",
                    value = "Tap",
                    valueColor = Color.White,
                    modifier = GlanceModifier.defaultWeight().fillMaxHeight(),
                )
            }
        }
    }

    // --------------------------------------------------------------------- //
    // Shared card primitives
    // --------------------------------------------------------------------- //

    @Composable
    private fun MetricCard(
        label: String,
        value: String,
        valueColor: Color,
        modifier: GlanceModifier = GlanceModifier,
    ) {
        CardSurface(modifier = modifier) {
            Column(
                modifier = GlanceModifier.fillMaxSize(),
                verticalAlignment = Alignment.Vertical.CenterVertically,
                horizontalAlignment = Alignment.Horizontal.Start,
            ) {
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
    }

    @Composable
    private fun CardSurface(
        modifier: GlanceModifier = GlanceModifier,
        content: @Composable () -> Unit,
    ) {
        Box(
            modifier = modifier
                .background(ColorProvider(CharcoalCard))
                .cornerRadius(12.dp)
                .padding(12.dp),
        ) {
            content()
        }
    }

    companion object {
        val SMALL_SIZE = DpSize(130.dp, 100.dp)
        val MEDIUM_SIZE = DpSize(276.dp, 100.dp)
        val LARGE_SIZE = DpSize(276.dp, 250.dp)

        private val OledBlack = Color(0xFF121212)
        private val CharcoalCard = Color(0xFF2A2A2A)
        private val MutedPrimary = Color(0x80D4D2CF)
        private val SurgicalTeal = Color(0xFF6B9A92)
        private val SoftCoral = Color(0xFFC17F74)
    }
}
