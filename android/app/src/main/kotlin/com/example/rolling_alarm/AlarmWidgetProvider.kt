package com.example.rolling_alarm

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class AlarmWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.alarm_widget)

            val routineName = widgetData.getString("routineName", "No Routine") ?: "No Routine"
            val nextTriggerDisplay =
                widgetData.getString("nextTriggerDisplay", "--:--:--") ?: "--:--:--"
            val routineId = widgetData.getString("routineId", null)

            views.setTextViewText(R.id.widget_routine_name, routineName)
            views.setTextViewText(R.id.widget_next_time, nextTriggerDisplay)

            val launchIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java
            )
            views.setOnClickPendingIntent(R.id.widget_root, launchIntent)

            if (routineId.isNullOrEmpty()) {
                views.setViewVisibility(R.id.widget_skip_button, View.GONE)
            } else {
                views.setViewVisibility(R.id.widget_skip_button, View.VISIBLE)
                val skipIntent = HomeWidgetBackgroundIntent.getBroadcast(
                    context,
                    Uri.parse("rollingalarm://skip?id=$routineId")
                )
                views.setOnClickPendingIntent(R.id.widget_skip_button, skipIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
