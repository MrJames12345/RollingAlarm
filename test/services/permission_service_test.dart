import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rolling_alarm/components/common/app_theme_scope.dart';
import 'package:rolling_alarm/components/common/oem_battery_guide_sheet.dart';
import 'package:rolling_alarm/enums/app_theme_mode.dart';
import 'package:rolling_alarm/services/permissions.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const permissionChannel = MethodChannel(
    'flutter.baseflow.com/permissions/methods',
  );
  const uiSchedulerChannel = MethodChannel(
    'com.casellaweb.rolling_alarm/alarm_ui_scheduler',
  );
  const notifChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );

  final permissionStatuses = <int, int>{};
  final requestedPermissions = <int>[];
  final notifChannelCalls = <MethodCall>[];
  var mockSdkInt = 34;
  var mockCanScheduleExact = true;
  var mockCanUseFsi = true;
  var mockIgnoringBattery = false;
  String? mockManufacturer = 'samsung';
  var batteryRequestCount = 0;
  Future<int?> Function(MethodCall call)? onRequestPermissionOverride;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, (MethodCall call) async {
          if (call.method == 'checkPermissionStatus') {
            final permId = call.arguments as int;
            return permissionStatuses[permId] ?? PermissionStatus.denied.index;
          }
          if (call.method == 'requestPermissions') {
            final ids = (call.arguments as List<Object?>).cast<int>();
            requestedPermissions.addAll(ids);
            if (onRequestPermissionOverride != null) {
              final custom = await onRequestPermissionOverride!(call);
              return <int, int>{
                for (final id in ids)
                  id: custom ?? permissionStatuses[id] ?? 0,
              };
            }
            return <int, int>{
              for (final id in ids) id: permissionStatuses[id] ?? 0,
            };
          }
          return null;
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(uiSchedulerChannel, (MethodCall call) async {
          return switch (call.method) {
            'getAndroidSdkInt' => mockSdkInt,
            'canScheduleExactAlarms' => mockCanScheduleExact,
            'canUseFullScreenIntent' => mockCanUseFsi,
            'isIgnoringBatteryOptimizations' => mockIgnoringBattery,
            'getDeviceManufacturer' => mockManufacturer,
            'requestIgnoreBatteryOptimizations' => () {
              batteryRequestCount++;
              return true;
            }(),
            _ => null,
          };
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifChannel, (MethodCall call) async {
          notifChannelCalls.add(call);
          return true;
        });
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    permissionStatuses.clear();
    requestedPermissions.clear();
    notifChannelCalls.clear();
    mockSdkInt = 34;
    mockCanScheduleExact = true;
    mockCanUseFsi = true;
    mockIgnoringBattery = false;
    mockManufacturer = 'samsung';
    batteryRequestCount = 0;
    onRequestPermissionOverride = null;
    RA_PermissionService.debugAllowOemSheetInTests = null;
    RA_ColourStyles.apply(AppThemeModeEnum.Dark);
  });

  tearDown(() {
    RA_PermissionService.debugAllowOemSheetInTests = null;
  });

  Widget buildHost(void Function(BuildContext) onContext) {
    return MaterialApp(
      theme: RA_AppTheme.themeData(),
      builder: (context, child) => RA_AppThemeScope(
        mode: AppThemeModeEnum.Dark,
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: Builder(
          builder: (ctx) {
            onContext(ctx);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  group('RA_PermissionService', () {
    test('getStatus aggregates all 5 live alarm reliability flags', () async {
      permissionStatuses[Permission.notification.value] =
          PermissionStatus.granted.index;
      permissionStatuses[Permission.systemAlertWindow.value] =
          PermissionStatus.denied.index;
      mockCanScheduleExact = true;
      mockCanUseFsi = false;
      mockIgnoringBattery = true;

      final status = await RA_PermissionService.getStatus();

      expect(status.notificationsGranted, isTrue);
      expect(status.exactAlarmsGranted, isTrue);
      expect(status.fullScreenIntentGranted, isFalse);
      expect(status.unrestrictedBatteryGranted, isTrue);
      expect(status.displayOverAppsGranted, isFalse);
    });

    testWidgets(
      'requests POST_NOTIFICATIONS at most once and never prompts SCHEDULE_EXACT_ALARM on API 33+',
      (tester) async {
        permissionStatuses[Permission.notification.value] =
            PermissionStatus.denied.index;
        permissionStatuses[Permission.scheduleExactAlarm.value] =
            PermissionStatus.denied.index;
        mockSdkInt = 33;
        mockCanScheduleExact = false;
        mockCanUseFsi = true;

        late BuildContext ctx;
        await tester.pumpWidget(buildHost((c) => ctx = c));

        await RA_PermissionService.ensureCoreAlarmPermissions(ctx);

        expect(requestedPermissions, equals([Permission.notification.value]));
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('ra_perm_notif_prompted'), isTrue);

        // Second invocation must not re-prompt notifications or exact alarms.
        requestedPermissions.clear();
        await RA_PermissionService.ensureCoreAlarmPermissions(ctx);
        expect(requestedPermissions, isEmpty);
      },
    );

    testWidgets(
      'requests SCHEDULE_EXACT_ALARM on API 31-32 when denied',
      (tester) async {
        permissionStatuses[Permission.notification.value] =
            PermissionStatus.granted.index;
        permissionStatuses[Permission.scheduleExactAlarm.value] =
            PermissionStatus.denied.index;
        mockSdkInt = 32;
        mockCanScheduleExact = false;

        late BuildContext ctx;
        await tester.pumpWidget(buildHost((c) => ctx = c));

        await RA_PermissionService.ensureCoreAlarmPermissions(ctx);

        expect(
          requestedPermissions,
          equals([Permission.scheduleExactAlarm.value]),
        );
      },
    );

    testWidgets(
      'Android 14+ shows Lock-Screen Alarm Alerts dialog once and opens settings on confirmation',
      (tester) async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        try {
          permissionStatuses[Permission.notification.value] =
              PermissionStatus.granted.index;
          mockSdkInt = 34;
          mockCanUseFsi = false;

          late BuildContext ctx;
          await tester.pumpWidget(buildHost((c) => ctx = c));

          final future = RA_PermissionService.ensureCoreAlarmPermissions(ctx);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          expect(find.text('Lock-Screen Alarm Alerts'), findsOneWidget);
          expect(find.text('Open Settings'), findsOneWidget);
          expect(find.text('Not Now'), findsOneWidget);

          await tester.tap(find.text('Open Settings'));
          await tester.pumpAndSettle();
          await future;

          expect(
            notifChannelCalls.any(
              (c) => c.method == 'requestFullScreenIntentPermission',
            ),
            isTrue,
          );
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getBool('ra_perm_fsi_prompted'), isTrue);

          // Calling again must not re-show the one-time FSI onboarding dialog.
          notifChannelCalls.clear();
          await RA_PermissionService.ensureCoreAlarmPermissions(ctx);
          await tester.pump();
          expect(find.text('Lock-Screen Alarm Alerts'), findsNothing);
          expect(notifChannelCalls, isEmpty);
        } finally {
          debugDefaultTargetPlatformOverride = previousPlatform;
        }
      },
    );

    testWidgets(
      'unmounted context before API 34+ FSI dialog does not burn ra_perm_fsi_prompted',
      (tester) async {
        permissionStatuses[Permission.notification.value] =
            PermissionStatus.denied.index;
        mockSdkInt = 34;
        mockCanUseFsi = false;

        final notifCompleter = Completer<int?>();
        onRequestPermissionOverride = (_) => notifCompleter.future;

        late BuildContext ctx;
        await tester.pumpWidget(buildHost((c) => ctx = c));

        final future = RA_PermissionService.ensureCoreAlarmPermissions(ctx);
        await tester.pump();

        // Unmount host while notification request is still in flight.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        notifCompleter.complete(PermissionStatus.granted.index);
        await future;

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('ra_perm_notif_prompted'), isTrue);
        // Must remain unset because the FSI dialog was never displayed.
        expect(prefs.getBool('ra_perm_fsi_prompted'), isNull);
      },
    );

    test(
      'RA_OemBatteryGuideContent resolves tailored copy for Samsung, Xiaomi, Oppo, Vivo, and generic Android',
      () {
        final samsung = RA_OemBatteryGuideContent.forManufacturer('Samsung');
        expect(samsung.brandBadge, contains('Samsung'));
        expect(samsung.bullets, hasLength(2));

        final xiaomi = RA_OemBatteryGuideContent.forManufacturer('POCO');
        expect(xiaomi.brandBadge, contains('Xiaomi'));
        expect(xiaomi.bullets, hasLength(2));

        final oppo = RA_OemBatteryGuideContent.forManufacturer('OnePlus');
        expect(oppo.brandBadge, contains('OnePlus'));
        expect(oppo.bullets, hasLength(2));

        final vivo = RA_OemBatteryGuideContent.forManufacturer('vivo');
        expect(vivo.brandBadge, contains('Vivo'));
        expect(vivo.bullets, hasLength(2));

        final generic = RA_OemBatteryGuideContent.forManufacturer('Google');
        expect(generic.brandBadge, contains('Android'));
        expect(generic.bullets, hasLength(2));
      },
    );

    testWidgets(
      'post-first-save OEM battery sheet appears once when unexempt, calls requestIgnoreBatteryOptimizations, and does not repeat',
      (tester) async {
        RA_PermissionService.debugAllowOemSheetInTests = true;
        permissionStatuses[Permission.notification.value] =
            PermissionStatus.granted.index;
        mockSdkInt = 34;
        mockCanUseFsi = true;
        mockIgnoringBattery = false;
        mockManufacturer = 'xiaomi';

        late BuildContext ctx;
        await tester.pumpWidget(buildHost((c) => ctx = c));

        final future = RA_PermissionService.ensureCoreAlarmPermissions(ctx);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byType(RA_OemBatteryGuideSheet), findsOneWidget);
        expect(find.text('Keep Xiaomi Alarms Reliable'), findsOneWidget);
        expect(find.text('Allow Unrestricted Battery'), findsOneWidget);
        expect(find.text('Later'), findsOneWidget);

        await tester.tap(find.text('Allow Unrestricted Battery'));
        await tester.pumpAndSettle();
        await future;

        expect(batteryRequestCount, equals(1));
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getBool(RA_PermissionService.oemBatteryPromptedKey),
          isTrue,
        );

        // Second call must not re-show the one-time sheet.
        await RA_PermissionService.ensureCoreAlarmPermissions(ctx);
        await tester.pump();
        expect(find.byType(RA_OemBatteryGuideSheet), findsNothing);
      },
    );

    testWidgets(
      'OEM battery sheet is skipped when already exempt or manufacturer channel is absent',
      (tester) async {
        RA_PermissionService.debugAllowOemSheetInTests = true;
        permissionStatuses[Permission.notification.value] =
            PermissionStatus.granted.index;
        mockSdkInt = 34;
        mockCanUseFsi = true;

        late BuildContext ctx;
        await tester.pumpWidget(buildHost((c) => ctx = c));

        // Already exempt -> skipped.
        mockIgnoringBattery = true;
        mockManufacturer = 'samsung';
        await RA_PermissionService.ensureCoreAlarmPermissions(ctx);
        await tester.pump();
        expect(find.byType(RA_OemBatteryGuideSheet), findsNothing);

        // Unexempt, but channel returned null -> skipped without burning flag.
        mockIgnoringBattery = false;
        mockManufacturer = null;
        await RA_PermissionService.ensureCoreAlarmPermissions(ctx);
        await tester.pump();
        expect(find.byType(RA_OemBatteryGuideSheet), findsNothing);
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getBool(RA_PermissionService.oemBatteryPromptedKey),
          isNull,
        );
      },
    );
  });
}
