import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rolling_alarm/components/common/alarm_ring_presenter.dart';
import 'package:rolling_alarm/components/common/app_theme_scope.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/app_theme_mode.dart';
import 'package:rolling_alarm/navigation/routes.dart';
import 'package:rolling_alarm/pages/home.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/notification.dart';
import 'package:rolling_alarm/services/purchase.dart';
import 'package:rolling_alarm/services/settings.dart';
import 'package:rolling_alarm/styles.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
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
  await RA_PurchaseService.init();
  final initialLegacyPro = await database.isLegacyProGrandfathered();
  RA_PurchaseService.setCachedLegacyPro(initialLegacyPro);
  unawaited(
    RA_PurchaseService.syncEffectiveProStatus(
      RA_PurchaseService.resolveEffectivePro(
        rcPro: RA_PurchaseService.cachedRcPro,
        legacyPro: initialLegacyPro,
      ),
    ),
  );
  // Re-arm from Drift after force-stop / missed native reboot restore.
  await RA_AlarmService.reconcileAlarmsOnStartup(db: database, dbPath: dbPath);
  unawaited(database.pruneOldLogs().catchError((Object _) {}));
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
      builder: (context, child) => RA_AppThemeScope(
        mode: themeMode,
        child: RA_ThemeRebuildGate(
          mode: themeMode,
          child: RA_AlarmRingPresenter(
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
      theme: RA_AppTheme.themeData(),
      home: HomePage(dbPath: dbPath),
    );
  }
}
