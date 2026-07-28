package com.example.rolling_alarm

import android.appwidget.AppWidgetManager
import android.content.Context
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver

/** Sole AppWidgetProvider for Rolling Alarm; hosts [RollingAlarmGlanceWidget]. */
class RollingAlarmWidgetReceiver :
    HomeWidgetGlanceWidgetReceiver<RollingAlarmGlanceWidget>() {
    override val glanceAppWidget = RollingAlarmGlanceWidget()

    /**
     * Flutter [es.antonborri.home_widget.HomeWidgetPlugin] broadcasts
     * [AppWidgetManager.ACTION_APPWIDGET_UPDATE] here after snooze / dismiss /
     * schedule. Re-read SQLite and force Glance to redraw (state bump included).
     */
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        WidgetRefresh.refreshAll(context)
    }
}
