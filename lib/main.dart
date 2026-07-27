import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rolling_alarm/components/common/alarm_ring_presenter.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/app_theme_mode.dart';
import 'package:rolling_alarm/navigation/routes.dart';
import 'package:rolling_alarm/pages/home.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/notification.dart';
import 'package:rolling_alarm/services/settings.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:rolling_alarm/utils.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dbPath = await RA_Database.resolveDatabasePath();
  // Persist before opening Drift / registering ports so a pending OS alarm
  // isolate can resolve the file even if reconcile has not run yet.
  await RA_AlarmService.persistDatabasePath(dbPath);
  final database = RA_Database();
  RA_NotificationService.bindUiDatabase(database);

  RA_AlarmService.registerUiPort(
    (_) => database.notifyUpdates({
      TableUpdate.onTable(database.routines),
      TableUpdate.onTable(database.routineStates),
      TableUpdate.onTable(database.logEntries),
    }),
  );

  await RA_AlarmService.init();
  await RA_NotificationService.init();
  await _requestPermissions();
  // Re-arm from Drift after force-stop / missed native reboot restore.
  await RA_AlarmService.reconcileAlarmsOnStartup(db: database, dbPath: dbPath);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final themeMode = await RA_SettingsService.getThemeMode();
  RA_ColourStyles.apply(themeMode);
  SystemChrome.setSystemUIOverlayStyle(RA_AppTheme.systemUiOverlayStyle());

  runApp(
    ProviderScope(
      overrides: [RA_DatabaseProvider.overrideWithValue(database)],
      child: RollingAlarmApp(dbPath: dbPath),
    ),
  );
}

Future<void> _requestPermissions() async {
  await RA_tryAsync(() async {
    if (!await Permission.notification.isGranted) {
      await Permission.notification.request();
    }
    if (!await Permission.scheduleExactAlarm.isGranted) {
      await Permission.scheduleExactAlarm.request();
    }
    // Native ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS is required for
    // Samsung / Xiaomi to keep AlarmReceiver + Drift isolates alive.
    await RA_AlarmService.ensureBatteryOptimizationExempt();
    // Android 14+: full-screen alarm UI needs USE_FULL_SCREEN_INTENT app-ops.
    await RA_NotificationService.requestFullScreenIntentPermission();
    // Lets the ring activity start over another foreground app when BAL blocks
    // plain startActivity from the wake service.
    if (!await Permission.systemAlertWindow.isGranted) {
      await Permission.systemAlertWindow.request();
    }
  });
}

class RollingAlarmApp extends ConsumerWidget {
  final String dbPath;
  const RollingAlarmApp({super.key, required this.dbPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode =
        ref.watch(AppThemeModeProvider).valueOrNull ?? AppThemeModeEnum.Dark;
    RA_ColourStyles.apply(themeMode);
    SystemChrome.setSystemUIOverlayStyle(RA_AppTheme.systemUiOverlayStyle());

    return MaterialApp(
      navigatorKey: RA_navigatorKey,
      title: 'Rolling Alarm',
      debugShowCheckedModeBanner: false,
      builder: (context, child) =>
          RA_AlarmRingPresenter(child: child ?? const SizedBox.shrink()),
      theme: RA_AppTheme.themeData(),
      home: HomePage(dbPath: dbPath),
    );
  }
}
