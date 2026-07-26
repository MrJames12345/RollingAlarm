import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rolling_alarm/components/common/alarm_ring_presenter.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/alarm_action_type_code.dart';
import 'package:rolling_alarm/navigation/routes.dart';
import 'package:rolling_alarm/pages/home.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/notification.dart';
import 'package:rolling_alarm/services/widget.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:rolling_alarm/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  await RA_WidgetService.registerBackgroundCallback(_homeWidgetCallback);
  await _requestPermissions();
  // Re-arm from Drift after force-stop / missed native reboot restore.
  await RA_AlarmService.reconcileAlarmsOnStartup(db: database, dbPath: dbPath);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: RA_ColourStyles.offBlack,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(
    ProviderScope(
      overrides: [RA_DatabaseProvider.overrideWithValue(database)],
      child: RollingAlarmApp(dbPath: dbPath),
    ),
  );
}

@pragma('vm:entry-point')
Future<void> _homeWidgetCallback(Uri? uri) async {
  try {
    if (uri?.host != 'skip') return;
    final routineId = int.tryParse(uri?.queryParameters['id'] ?? '');
    if (routineId == null) return;
    final dbPath = (await SharedPreferences.getInstance()).getString(
      'ra_db_path',
    );
    if (dbPath == null) return;
    final db = RA_Database.openForIsolate(dbPath);
    try {
      final routine = await db.getRoutineById(routineId);
      final state = await db.getRoutineState(routineId);
      if (state != null) {
        await RA_AlarmService.handleTransition(
          action: RA_AlarmActionTypeCodeEnum.Skip,
          routineId: routineId,
          db: db,
          routine: routine,
          state: state,
        );
      }
    } finally {
      await db.close();
    }
  } catch (_) {}
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
  });
}

class RollingAlarmApp extends StatelessWidget {
  final String dbPath;
  const RollingAlarmApp({super.key, required this.dbPath});

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: RA_navigatorKey,
    title: 'Rolling Alarm',
    debugShowCheckedModeBanner: false,
    builder: (context, child) => RA_AlarmRingPresenter(
      child: child ?? const SizedBox.shrink(),
    ),
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: RA_ColourStyles.offBlack,
      canvasColor: RA_ColourStyles.offBlack,
      cardColor: RA_ColourStyles.surface,
      dividerColor: RA_ColourStyles.surface,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      colorScheme: ColorScheme.dark(
        primary: RA_ColourStyles.secondary,
        secondary: RA_ColourStyles.secondary,
        // Absolute OLED black for scaffold-level surfaces; charcoal only for
        // intentional elevated tokens. Pin every M3 container so Material never
        // injects washed-out default greys.
        surface: RA_ColourStyles.offBlack,
        surfaceDim: RA_ColourStyles.offBlack,
        surfaceBright: RA_ColourStyles.surface,
        surfaceContainerLowest: RA_ColourStyles.offBlack,
        surfaceContainerLow: RA_ColourStyles.offBlack,
        surfaceContainer: RA_ColourStyles.surface,
        surfaceContainerHigh: RA_ColourStyles.surface,
        surfaceContainerHighest: RA_ColourStyles.surface,
        surfaceTint: RA_ColourStyles.secondary,
        error: RA_ColourStyles.softCoral,
        onPrimary: RA_ColourStyles.offBlack,
        onSecondary: RA_ColourStyles.offBlack,
        onSurface: RA_ColourStyles.primary,
        onSurfaceVariant: RA_ColourStyles.primary.withValues(alpha: 0.55),
        onError: RA_ColourStyles.offBlack,
        outline: RA_ColourStyles.secondary.withValues(alpha: 0.28),
        outlineVariant: RA_ColourStyles.secondary.withValues(alpha: 0.1),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: RA_ColourStyles.offBlack,
        foregroundColor: RA_ColourStyles.primary,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: RA_ColourStyles.primary, size: 24),
        actionsIconTheme: IconThemeData(
          color: RA_ColourStyles.primary,
          size: 24,
        ),
        titleTextStyle: RA_TextStyles.largeFont,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(
            RA_ShapeStyles.minTouchTarget,
            RA_ShapeStyles.minTouchTarget,
          ),
          tapTargetSize: MaterialTapTargetSize.padded,
          foregroundColor: RA_ColourStyles.primary,
          overlayColor: RA_ColourStyles.secondary.withValues(alpha: 0.12),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: RA_ColourStyles.secondary,
        foregroundColor: RA_ColourStyles.offBlack,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        splashColor: RA_ColourStyles.primary.withValues(alpha: 0.22),
        shape: const RoundedRectangleBorder(
          borderRadius: RA_ShapeStyles.largeBorderRadius,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shadowColor: RA_ColourStyles.secondary,
          minimumSize: const Size(
            RA_ShapeStyles.minTouchTarget,
            RA_ShapeStyles.minTouchTarget + RA_ShapeStyles.space8,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: RA_ShapeStyles.largeBorderRadius,
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: RA_ColourStyles.secondary.withValues(alpha: 0.08),
        iconColor: RA_ColourStyles.primary,
        textColor: RA_ColourStyles.primary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: RA_ShapeStyles.space16,
        ),
        minVerticalPadding: RA_ShapeStyles.space8,
        minTileHeight: RA_ShapeStyles.minTouchTarget,
        shape: const RoundedRectangleBorder(
          borderRadius: RA_ShapeStyles.largeBorderRadius,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: RA_ColourStyles.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: RA_ShapeStyles.largeBorderRadius,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return RA_ColourStyles.secondary;
          }
          return RA_ColourStyles.primary.withValues(alpha: 0.55);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return RA_ColourStyles.secondary.withValues(alpha: 0.28);
          }
          return RA_ColourStyles.primary.withValues(alpha: 0.12);
        }),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return RA_ColourStyles.secondary;
          }
          return RA_ColourStyles.primary.withValues(alpha: 0.45);
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: RA_ColourStyles.secondary,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: RA_ColourStyles.secondary,
        selectionColor: RA_ColourStyles.secondary.withValues(alpha: 0.2),
        selectionHandleColor: RA_ColourStyles.secondary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: RA_ColourStyles.surface,
        contentTextStyle: RA_TextStyles.smallFont,
        actionTextColor: RA_ColourStyles.secondary,
      ),
    ),
    home: HomePage(dbPath: dbPath),
  );
}
