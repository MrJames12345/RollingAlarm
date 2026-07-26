package com.example.rolling_alarm

import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver

/** Sole AppWidgetProvider for Rolling Alarm; hosts [RollingAlarmGlanceWidget]. */
class RollingAlarmWidgetReceiver :
    HomeWidgetGlanceWidgetReceiver<RollingAlarmGlanceWidget>() {
    override val glanceAppWidget = RollingAlarmGlanceWidget()
}
