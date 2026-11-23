# Rolling Alarm R8 / ProGuard release hardening rules

# Preserve generic signatures, annotations, and inner-class metadata required by
# Gson TypeToken deserialization (flutter_local_notifications), RevenueCat, and Kotlin.
-keepattributes InnerClasses, Signature, *Annotation*, EnclosingMethod, SourceFile, LineNumberTable

# flutter_local_notifications + Gson TypeToken
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# XML pull parser (referenced by third-party notification/asset libraries)
-keep class org.xmlpull.** { *; }
-dontwarn org.xmlpull.**

# RevenueCat Purchases SDK & Google Play Billing Library v8/v9
-keep class com.revenuecat.purchases.** { *; }
-keep class com.android.billingclient.api.** { *; }
-dontwarn com.revenuecat.purchases.**

# Jetpack Glance & AndroidX DataStore home screen widget
-keep class androidx.glance.** { *; }
-keep class androidx.datastore.** { *; }
-keep class es.antonborri.home_widget.** { *; }

# android_alarm_manager_plus background callback & boot receivers
-keep class dev.fluttercommunity.plus.androidalarmmanager.** { *; }

# Rolling Alarm native entry points, receivers, services, plugins, and Glance widget
-keep class com.casellaweb.rolling_alarm.MainActivity { *; }
-keep class com.casellaweb.rolling_alarm.AlarmReceiver { *; }
-keep class com.casellaweb.rolling_alarm.AlarmRingingService { *; }
-keep class com.casellaweb.rolling_alarm.AlarmResurrectionReceiver { *; }
-keep class com.casellaweb.rolling_alarm.AlarmUiSchedulerPlugin { *; }
-keep class com.casellaweb.rolling_alarm.AlarmSqliteGate { *; }
-keep class com.casellaweb.rolling_alarm.AlarmRingDisplayGate { *; }
-keep class com.casellaweb.rolling_alarm.AlarmRingtonePlayer { *; }
-keep class com.casellaweb.rolling_alarm.AlarmVibrator { *; }
-keep class com.casellaweb.rolling_alarm.RollingAlarmWidgetReceiver { *; }
-keep class com.casellaweb.rolling_alarm.RollingAlarmGlanceWidget { *; }
-keep class com.casellaweb.rolling_alarm.WidgetConfigActivity { *; }
-keep class com.casellaweb.rolling_alarm.WidgetRefresh { *; }
-keep class com.casellaweb.rolling_alarm.WidgetRoutineBridge { *; }
