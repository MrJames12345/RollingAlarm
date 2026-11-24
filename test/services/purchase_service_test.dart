import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:rolling_alarm/components/common/app_theme_scope.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/app_theme_mode.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';
import 'package:rolling_alarm/pages/home.dart';
import 'package:rolling_alarm/pages/paywall.dart';
import 'package:rolling_alarm/pages/routine_edit.dart';
import 'package:rolling_alarm/pages/settings.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/purchase.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

class _MockOfferings extends Mock implements Offerings {}

class _MockOffering extends Mock implements Offering {}

class _MockPackage extends Mock implements Package {}

class _MockStoreProduct extends Mock implements StoreProduct {}

Future<void> _seedRoutine(
  RA_Database db, {
  required String name,
  required DateTime nextTrigger,
}) async {
  await db.insertRoutineWithInitialState(
    routine: RoutinesCompanion(
      Name: Value(name),
      IntervalSeconds: const Value(14400),
      SnoozeSeconds: const Value(300),
      DriftCompensationTypeCode: Value(
        DriftCompensationTypeCodeEnum.ActualDismissal.index,
      ),
    ),
    nextTriggerTime: nextTrigger,
  );
}

/// Builds a v17 SQLite file with [routineNames] so opening it via Drift
/// runs the real v17 -> v18 grandfathering upgrade.
({Directory tempDir, String dbPath}) _createV17DatabaseFile(
  List<String> routineNames,
) {
  final tempDir = Directory.systemTemp.createTempSync('ra_pro_v17_');
  final dbPath = p.join(tempDir.path, 'legacy_v17.db');
  final raw = sqlite3.sqlite3.open(dbPath);
  try {
    raw.execute('''
      CREATE TABLE routines (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        snooze_seconds INTEGER NOT NULL DEFAULT 300,
        interval_seconds INTEGER NOT NULL,
        max_times_per_day INTEGER NOT NULL DEFAULT 0,
        day_start_seconds INTEGER NOT NULL DEFAULT 0,
        max_times_per_day_enabled INTEGER NOT NULL DEFAULT 0,
        enabled_weekdays INTEGER NOT NULL DEFAULT 127,
        drift_compensation_type_code INTEGER NOT NULL,
        show_preview INTEGER NOT NULL DEFAULT 1,
        vibrate INTEGER NOT NULL DEFAULT 1,
        volume INTEGER NOT NULL DEFAULT 50,
        fade_in INTEGER NOT NULL DEFAULT 0,
        audio_uri TEXT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
        modified_at INTEGER NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      );
    ''');
    raw.execute('''
      CREATE TABLE routine_states (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        routine_id INTEGER NOT NULL UNIQUE,
        next_trigger_time INTEGER NULL,
        initial_ring_time INTEGER NULL,
        is_ringing INTEGER NOT NULL DEFAULT 0,
        current_snooze_count INTEGER NOT NULL DEFAULT 0,
        times_ring_today INTEGER NOT NULL DEFAULT 0,
        extra_max_times_today INTEGER NOT NULL DEFAULT 0,
        times_ring_day INTEGER NULL,
        last_dismissed_at INTEGER NULL,
        paused_at INTEGER NULL,
        muted_at INTEGER NULL,
        created_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
        modified_at INTEGER NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      );
    ''');
    raw.execute('''
      CREATE TABLE log_entries (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        routine_id INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        log_action_type_code INTEGER NOT NULL,
        time_since_last_dismissal_seconds INTEGER NULL,
        was_muted INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
        modified_at INTEGER NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      );
    ''');

    final futureSec =
        DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch ~/
        1000;
    for (var i = 0; i < routineNames.length; i++) {
      raw.execute(
        'INSERT INTO routines (name, interval_seconds, drift_compensation_type_code) '
        'VALUES (?, 14400, 0);',
        [routineNames[i]],
      );
      final routineId = raw.lastInsertRowId;
      raw.execute(
        'INSERT INTO routine_states (routine_id, next_trigger_time) VALUES (?, ?);',
        [routineId, futureSec],
      );
    }
    raw.execute('PRAGMA user_version = 17;');
  } finally {
    raw.close();
  }
  return (tempDir: tempDir, dbPath: dbPath);
}

class _ProRootListener extends ConsumerWidget {
  final Widget child;

  const _ProRootListener({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mirrors RA_AlarmRingPresenter keeping IsProProvider active at app root.
    ref.watch(IsProProvider);
    return child;
  }
}

Widget _buildHomeTestApp({
  required RA_Database db,
  required String dbPath,
  required DateTime fixedNow,
  List<Override> extraOverrides = const [],
}) {
  RA_ColourStyles.apply(AppThemeModeEnum.Dark);
  return ProviderScope(
    overrides: [
      RA_DatabaseProvider.overrideWithValue(db),
      WallClockSecondProvider.overrideWith((ref) => Stream.value(fixedNow)),
      OfferingsProvider.overrideWith((ref) async => null),
      ...extraOverrides,
    ],
    child: MaterialApp(
      theme: RA_AppTheme.themeData(),
      builder: (context, child) => RA_AppThemeScope(
        mode: AppThemeModeEnum.Dark,
        child: _ProRootListener(child: child ?? const SizedBox.shrink()),
      ),
      home: HomePage(dbPath: dbPath),
    ),
  );
}

Future<void> _disposeWidgetTree(WidgetTester tester, RA_Database db) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // Flush Drift's StreamQueryStore.markAsClosed zero-duration cleanup timer.
  await tester.pump(Duration.zero);
  await db.close();
}

void main() {
  final homeWidgetCalls = <MethodCall>[];

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

    const homeWidgetChannel = MethodChannel('home_widget');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(homeWidgetChannel, (MethodCall call) async {
          homeWidgetCalls.add(call);
          return true;
        });

    const alarmSoundChannel = MethodChannel(
      'com.casellaweb.rolling_alarm/alarm_sound',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(alarmSoundChannel, (MethodCall call) async {
          if (call.method == 'getSystemAlarmVolume') {
            return 0.5;
          }
          return null;
        });

    const uiSchedulerChannel = MethodChannel(
      'com.casellaweb.rolling_alarm/alarm_ui_scheduler',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(uiSchedulerChannel, (MethodCall call) async {
          return true;
        });
  });

  setUp(() {
    RA_PurchaseService.resetForTesting();
    SharedPreferences.setMockInitialValues({});
    homeWidgetCalls.clear();
  });

  tearDown(() {
    RA_PurchaseService.resetForTesting();
  });

  group('RA_PurchaseService Day-0 Founding Lifetime Countdown', () {
    test(
      'persists first_seen on initial call and returns full 24h window',
      () async {
        final t0 = DateTime.utc(2026, 6, 1, 9, 0, 0);

        final remaining = await RA_PurchaseService.foundingOfferRemaining(
          now: t0,
        );

        expect(remaining, equals(const Duration(hours: 24)));
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getInt(RA_PurchaseService.firstSeenEpochMsKey),
          equals(t0.millisecondsSinceEpoch),
        );
        expect(
          RA_PurchaseService.foundingOfferRemainingSync(now: t0),
          equals(const Duration(hours: 24)),
        );
      },
    );

    test(
      'computes active remaining duration mid-window and just before expiry',
      () async {
        final firstSeen = DateTime.utc(2026, 6, 1, 8, 0, 0);
        SharedPreferences.setMockInitialValues({
          RA_PurchaseService.firstSeenEpochMsKey:
              firstSeen.millisecondsSinceEpoch,
        });

        final midWindow = firstSeen.add(
          const Duration(hours: 6, minutes: 15, seconds: 30),
        );
        final midRemaining = await RA_PurchaseService.foundingOfferRemaining(
          now: midWindow,
        );
        expect(
          midRemaining,
          equals(const Duration(hours: 17, minutes: 44, seconds: 30)),
        );

        final oneSecondLeft = firstSeen.add(
          const Duration(hours: 23, minutes: 59, seconds: 59),
        );
        expect(
          RA_PurchaseService.foundingOfferRemainingSync(now: oneSecondLeft),
          equals(const Duration(seconds: 1)),
        );
      },
    );

    test(
      'returns Duration.zero at exact 24h boundary and after expiration',
      () async {
        final firstSeen = DateTime.utc(2026, 6, 1, 8, 0, 0);
        SharedPreferences.setMockInitialValues({
          RA_PurchaseService.firstSeenEpochMsKey:
              firstSeen.millisecondsSinceEpoch,
        });

        final exactExpiry = firstSeen.add(const Duration(hours: 24));
        expect(
          await RA_PurchaseService.foundingOfferRemaining(now: exactExpiry),
          equals(Duration.zero),
        );
        expect(
          RA_PurchaseService.foundingOfferRemainingSync(now: exactExpiry),
          equals(Duration.zero),
        );

        final pastExpiry = firstSeen.add(const Duration(hours: 30));
        expect(
          await RA_PurchaseService.foundingOfferRemaining(now: pastExpiry),
          equals(Duration.zero),
        );
        expect(
          RA_PurchaseService.foundingOfferRemainingSync(now: pastExpiry),
          equals(Duration.zero),
        );
      },
    );

    test(
      'clamps backward device clock skew to 24h max and init preserves stored first_seen',
      () async {
        final firstSeen = DateTime.utc(2026, 6, 10, 12, 0, 0);
        SharedPreferences.setMockInitialValues({
          RA_PurchaseService.firstSeenEpochMsKey:
              firstSeen.millisecondsSinceEpoch,
        });

        await RA_PurchaseService.init();

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getInt(RA_PurchaseService.firstSeenEpochMsKey),
          equals(firstSeen.millisecondsSinceEpoch),
        );

        // Device clock moved backwards by 5 hours -> clamped to 24h window.
        final skewedBack = firstSeen.subtract(const Duration(hours: 5));
        expect(
          await RA_PurchaseService.foundingOfferRemaining(now: skewedBack),
          equals(RA_PurchaseService.foundingOfferWindow),
        );
      },
    );
  });

  group('RA_PurchaseService Effective isPro Resolution & Offline Cache', () {
    test(
      'resolveEffectivePro combines rcPro, legacyPro, and debugOverrideIsPro',
      () {
        expect(
          RA_PurchaseService.resolveEffectivePro(rcPro: false, legacyPro: false),
          isFalse,
        );
        expect(
          RA_PurchaseService.resolveEffectivePro(rcPro: true, legacyPro: false),
          isTrue,
        );
        expect(
          RA_PurchaseService.resolveEffectivePro(rcPro: false, legacyPro: true),
          isTrue,
        );
        expect(
          RA_PurchaseService.resolveEffectivePro(rcPro: true, legacyPro: true),
          isTrue,
        );

        RA_PurchaseService.debugOverrideIsPro = true;
        expect(
          RA_PurchaseService.resolveEffectivePro(rcPro: false, legacyPro: false),
          isTrue,
        );

        RA_PurchaseService.debugOverrideIsPro = false;
        expect(
          RA_PurchaseService.resolveEffectivePro(rcPro: true, legacyPro: true),
          isFalse,
        );
      },
    );

    test(
      'IsProProvider reflects cached offline RevenueCat entitlement on fresh v18 DB',
      () async {
        SharedPreferences.setMockInitialValues({
          RA_PurchaseService.rcIsProCachedKey: true,
        });
        await RA_PurchaseService.init();

        final db = RA_Database.forTesting(NativeDatabase.memory());
        final container = ProviderContainer(
          overrides: [RA_DatabaseProvider.overrideWithValue(db)],
        );
        addTearDown(() async {
          container.dispose();
          await db.close();
        });

        expect(await container.read(RevenueCatProProvider.future), isTrue);
        expect(
          await container.read(LegacyProGrandfatheredProvider.future),
          isFalse,
        );
        expect(container.read(IsProProvider), isTrue);
      },
    );

    test(
      'IsProProvider is true for live RevenueCat stream even when offline cache and legacy are false',
      () async {
        SharedPreferences.setMockInitialValues({
          RA_PurchaseService.rcIsProCachedKey: false,
        });
        await RA_PurchaseService.init();

        final db = RA_Database.forTesting(NativeDatabase.memory());
        final container = ProviderContainer(
          overrides: [
            RA_DatabaseProvider.overrideWithValue(db),
            RevenueCatProProvider.overrideWith((ref) => Stream.value(true)),
          ],
        );
        addTearDown(() async {
          container.dispose();
          await db.close();
        });

        expect(await container.read(RevenueCatProProvider.future), isTrue);
        expect(
          await container.read(LegacyProGrandfatheredProvider.future),
          isFalse,
        );
        expect(container.read(IsProProvider), isTrue);
      },
    );

    test(
      'IsProProvider is true for Drift v18 grandfathered v1.0.1 upgrade and syncs native prefs',
      () async {
        SharedPreferences.setMockInitialValues({
          RA_PurchaseService.rcIsProCachedKey: false,
        });
        await RA_PurchaseService.init();

        final legacy = _createV17DatabaseFile(['Early Adopter Alarm']);
        final db = RA_Database.openForIsolate(legacy.dbPath);
        final container = ProviderContainer(
          overrides: [RA_DatabaseProvider.overrideWithValue(db)],
        );
        addTearDown(() async {
          container.dispose();
          await db.close();
          if (legacy.tempDir.existsSync()) {
            legacy.tempDir.deleteSync(recursive: true);
          }
        });

        expect(await db.isLegacyProGrandfathered(), isTrue);
        expect(await container.read(RevenueCatProProvider.future), isFalse);
        expect(
          await container.read(LegacyProGrandfatheredProvider.future),
          isTrue,
        );
        expect(container.read(IsProProvider), isTrue);
        expect(RA_PurchaseService.cachedLegacyPro, isTrue);

        // Drain the event loop WITHOUT manually invoking syncEffectiveProStatus,
        // proving LegacyProGrandfatheredProvider itself syncs native prefs and
        // HomeWidget when grandfathering resolves.
        final prefs = await SharedPreferences.getInstance();
        for (var i = 0; i < 20; i++) {
          if (prefs.getBool(RA_PurchaseService.isProEffectiveKey) == true &&
              homeWidgetCalls.isNotEmpty) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(prefs.getBool(RA_PurchaseService.isProEffectiveKey), isTrue);
        expect(
          homeWidgetCalls.any((c) {
            if (c.method != 'saveWidgetData') return false;
            final args = c.arguments as Map<Object?, Object?>?;
            return args?['id'] == RA_PurchaseService.widgetIsProKey &&
                args?['data'] == true;
          }),
          isTrue,
        );
      },
    );

    test(
      'watchRcPro hydrates cached offline entitlement even before init() is called',
      () async {
        SharedPreferences.setMockInitialValues({
          RA_PurchaseService.rcIsProCachedKey: true,
        });
        expect(RA_PurchaseService.isInitialized, isFalse);

        final first = await RA_PurchaseService.watchRcPro().first;
        expect(first, isTrue);
        expect(RA_PurchaseService.cachedRcPro, isTrue);
      },
    );

    test(
      'syncEffectiveProStatusIfChanged deduplicates repeated writes and re-syncs on change',
      () async {
        await RA_PurchaseService.syncEffectiveProStatusIfChanged(false);
        expect(homeWidgetCalls.length, equals(1));

        await RA_PurchaseService.syncEffectiveProStatusIfChanged(false);
        expect(homeWidgetCalls.length, equals(1));

        await RA_PurchaseService.syncEffectiveProStatusIfChanged(true);
        expect(homeWidgetCalls.length, equals(2));
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(RA_PurchaseService.isProEffectiveKey), isTrue);
      },
    );

    test(
      'syncEffectiveProStatusIfChanged preserves rapid true -> false -> true transition while queued',
      () async {
        await RA_PurchaseService.syncEffectiveProStatusIfChanged(true);
        expect(homeWidgetCalls.length, equals(1));

        final holdFalseWrite = Completer<bool>();
        const homeWidgetChannel = MethodChannel('home_widget');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(homeWidgetChannel, (MethodCall call) async {
              homeWidgetCalls.add(call);
              final args = call.arguments as Map<Object?, Object?>?;
              if (args?['data'] == false && !holdFalseWrite.isCompleted) {
                return holdFalseWrite.future;
              }
              return true;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(homeWidgetChannel, (MethodCall call) async {
                homeWidgetCalls.add(call);
                return true;
              });
        });

        final falseSync = RA_PurchaseService.syncEffectiveProStatusIfChanged(
          false,
        );
        // Flip back to true BEFORE the false write finishes.
        final trueSync = RA_PurchaseService.syncEffectiveProStatusIfChanged(
          true,
        );
        holdFalseWrite.complete(true);
        await Future.wait([falseSync, trueSync]);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(RA_PurchaseService.isProEffectiveKey), isTrue);
        final lastArgs =
            homeWidgetCalls.last.arguments as Map<Object?, Object?>?;
        expect(lastArgs?['data'], isTrue);
      },
    );

    test(
      'IsProProvider is false on fresh v18 install with no RevenueCat entitlement',
      () async {
        SharedPreferences.setMockInitialValues({
          RA_PurchaseService.rcIsProCachedKey: false,
        });
        await RA_PurchaseService.init();

        final db = RA_Database.forTesting(NativeDatabase.memory());
        final container = ProviderContainer(
          overrides: [RA_DatabaseProvider.overrideWithValue(db)],
        );
        addTearDown(() async {
          container.dispose();
          await db.close();
        });

        expect(await container.read(RevenueCatProProvider.future), isFalse);
        expect(
          await container.read(LegacyProGrandfatheredProvider.future),
          isFalse,
        );
        expect(container.read(IsProProvider), isFalse);
      },
    );

    test(
      'productMatchesSku and findPackageForTier handle Play base-plan IDs without falling back foundingLifetime to standard lifetime',
      () {
        expect(
          RA_PurchaseService.productMatchesSku(
            'rolling_alarm_pro_annual:annual-base',
            RA_PurchaseService.annualSku,
          ),
          isTrue,
        );
        expect(
          RA_PurchaseService.productMatchesSku(
            'rolling_alarm_pro_lifetime_founding',
            RA_PurchaseService.lifetimeSku,
          ),
          isFalse,
        );

        final lifetimeProduct = _MockStoreProduct();
        when(
          () => lifetimeProduct.identifier,
        ).thenReturn(RA_PurchaseService.lifetimeSku);

        final lifetimePkg = _MockPackage();
        when(() => lifetimePkg.identifier).thenReturn(r'$rc_lifetime');
        when(() => lifetimePkg.storeProduct).thenReturn(lifetimeProduct);

        final annualProduct = _MockStoreProduct();
        when(
          () => annualProduct.identifier,
        ).thenReturn('${RA_PurchaseService.annualSku}:yearly-base');

        final annualPkg = _MockPackage();
        when(() => annualPkg.identifier).thenReturn(r'$rc_annual');
        when(() => annualPkg.storeProduct).thenReturn(annualProduct);

        final offering = _MockOffering();
        when(() => offering.identifier).thenReturn('default');
        when(
          () => offering.availablePackages,
        ).thenReturn([lifetimePkg, annualPkg]);
        when(() => offering.lifetime).thenReturn(lifetimePkg);
        when(() => offering.annual).thenReturn(annualPkg);
        when(() => offering.monthly).thenReturn(null);

        final offerings = _MockOfferings();
        when(() => offerings.current).thenReturn(offering);
        when(() => offerings.all).thenReturn({'default': offering});

        expect(
          RA_PurchaseService.findPackageForTier(
            offerings,
            RA_PurchaseTier.foundingLifetime,
          ),
          isNull,
        );
        expect(
          RA_PurchaseService.findPackageForTier(
            offerings,
            RA_PurchaseTier.lifetime,
          ),
          equals(lifetimePkg),
        );
        expect(
          RA_PurchaseService.findPackageForTier(
            offerings,
            RA_PurchaseTier.annual,
          ),
          equals(annualPkg),
        );

        // Pass-2 guard: standard lifetime must NEVER match a founding SKU even
        // when offering.lifetime points to the founding product; and founding
        // lookup searches secondary offerings in offerings.all.
        final foundingProduct = _MockStoreProduct();
        when(
          () => foundingProduct.identifier,
        ).thenReturn(RA_PurchaseService.foundingLifetimeSku);
        final foundingPkg = _MockPackage();
        when(() => foundingPkg.identifier).thenReturn('founding_day0');
        when(() => foundingPkg.storeProduct).thenReturn(foundingProduct);

        final foundingOnlyCurrent = _MockOffering();
        when(() => foundingOnlyCurrent.identifier).thenReturn('promo');
        when(
          () => foundingOnlyCurrent.availablePackages,
        ).thenReturn([foundingPkg]);
        when(() => foundingOnlyCurrent.lifetime).thenReturn(foundingPkg);
        when(() => foundingOnlyCurrent.annual).thenReturn(null);
        when(() => foundingOnlyCurrent.monthly).thenReturn(null);

        final secondaryOfferings = _MockOfferings();
        when(() => secondaryOfferings.current).thenReturn(foundingOnlyCurrent);
        when(() => secondaryOfferings.all).thenReturn({
          'promo': foundingOnlyCurrent,
        });

        expect(
          RA_PurchaseService.findPackageForTier(
            secondaryOfferings,
            RA_PurchaseTier.lifetime,
          ),
          isNull,
        );
        expect(
          RA_PurchaseService.findPackageForTier(
            secondaryOfferings,
            RA_PurchaseTier.foundingLifetime,
          ),
          equals(foundingPkg),
        );

        // Secondary offering lookup when current lacks foundingLifetime.
        final crossOfferings = _MockOfferings();
        when(() => crossOfferings.current).thenReturn(offering);
        when(() => crossOfferings.all).thenReturn({
          'default': offering,
          'promo': foundingOnlyCurrent,
        });
        expect(
          RA_PurchaseService.findPackageForTier(
            crossOfferings,
            RA_PurchaseTier.foundingLifetime,
          ),
          equals(foundingPkg),
        );
      },
    );

    test(
      'purchaseTier and restorePurchases fail soft with notConfigured when API key is blank',
      () async {
        final purchaseOutcome = await RA_PurchaseService.purchaseTier(
          RA_PurchaseTier.lifetime,
        );
        expect(purchaseOutcome.status, equals(RA_PurchaseStatus.notConfigured));
        expect(purchaseOutcome.isPro, isFalse);

        final restoreOutcome = await RA_PurchaseService.restorePurchases();
        expect(restoreOutcome.status, equals(RA_PurchaseStatus.notConfigured));
        expect(restoreOutcome.isPro, isFalse);
      },
    );
  });

  group('Free-Tier 2-Routine Limit Enforcement vs Grandfathered v1.0.1 Bypass', () {
    testWidgets(
      'free user with 1 live routine can open RoutineEditPage via FAB',
      (tester) async {
        final db = RA_Database.forTesting(NativeDatabase.memory());
        final now = DateTime.now();
        await _seedRoutine(
          db,
          name: 'Morning Meds',
          nextTrigger: now.add(const Duration(hours: 2)),
        );
        await RA_PurchaseService.init();

        try {
          await tester.pumpWidget(
            _buildHomeTestApp(db: db, dbPath: ':memory:', fixedNow: now),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          expect(find.text('Morning Meds'), findsOneWidget);

          await tester.tap(find.byType(FloatingActionButton));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(RoutineEditPage), findsOneWidget);
          expect(find.byType(PaywallPage), findsNothing);
        } finally {
          await _disposeWidgetTree(tester, db);
        }
      },
    );

    testWidgets(
      'free user at 2-routine limit is gated to PaywallPage instead of RoutineEditPage',
      (tester) async {
        final db = RA_Database.forTesting(NativeDatabase.memory());
        final now = DateTime.now();
        await _seedRoutine(
          db,
          name: 'Routine One',
          nextTrigger: now.add(const Duration(hours: 1)),
        );
        await _seedRoutine(
          db,
          name: 'Routine Two',
          nextTrigger: now.add(const Duration(hours: 3)),
        );
        await RA_PurchaseService.init();

        try {
          await tester.pumpWidget(
            _buildHomeTestApp(db: db, dbPath: ':memory:', fixedNow: now),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          expect(await db.countLiveRoutines(), equals(2));

          await tester.tap(find.byType(FloatingActionButton));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(PaywallPage), findsOneWidget);
          expect(
            find.text('Create unlimited rolling routines with Pro'),
            findsOneWidget,
          );
          expect(find.byType(RoutineEditPage), findsNothing);

          // Dismiss paywall and confirm RoutineEditPage was not pushed.
          await tester.tap(find.byTooltip('Close'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(PaywallPage), findsNothing);
          expect(find.byType(RoutineEditPage), findsNothing);
          expect(PaywallPage.isShowing, isFalse);
        } finally {
          await _disposeWidgetTree(tester, db);
        }
      },
    );

    testWidgets(
      'soft-deleted routines do not count against free 2-routine limit',
      (tester) async {
        final db = RA_Database.forTesting(NativeDatabase.memory());
        final now = DateTime.now();
        await _seedRoutine(
          db,
          name: 'Active Routine',
          nextTrigger: now.add(const Duration(hours: 1)),
        );
        final toDeleteId = await db.insertRoutineWithInitialState(
          routine: RoutinesCompanion(
            Name: const Value('Deleted Routine'),
            IntervalSeconds: const Value(7200),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
          ),
          nextTriggerTime: now.add(const Duration(hours: 2)),
        );
        await db.softDeleteRoutine(toDeleteId);
        await RA_PurchaseService.init();

        try {
          await tester.pumpWidget(
            _buildHomeTestApp(db: db, dbPath: ':memory:', fixedNow: now),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          expect(await db.countLiveRoutines(), equals(1));

          await tester.tap(find.byType(FloatingActionButton));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(RoutineEditPage), findsOneWidget);
          expect(find.byType(PaywallPage), findsNothing);
        } finally {
          await _disposeWidgetTree(tester, db);
        }
      },
    );

    testWidgets(
      'grandfathered v1.0.1 upgrader with 2+ routines bypasses 2-routine limit and opens RoutineEditPage',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          RA_PurchaseService.rcIsProCachedKey: false,
        });
        await RA_PurchaseService.init();

        final legacy = _createV17DatabaseFile([
          'Legacy Routine 1',
          'Legacy Routine 2',
        ]);
        // NativeDatabase.opened avoids async dart:io File checks inside FakeAsync
        // while still running the real SQLite v17 -> v18 migration on disk.
        final db = RA_Database.forTesting(
          NativeDatabase.opened(sqlite3.sqlite3.open(legacy.dbPath)),
        );
        final now = DateTime.now();

        try {
          expect(await db.isLegacyProGrandfathered(), isTrue);
          expect(await db.countLiveRoutines(), equals(2));

          await tester.pumpWidget(
            _buildHomeTestApp(db: db, dbPath: legacy.dbPath, fixedNow: now),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          expect(find.text('Legacy Routine 1'), findsOneWidget);
          expect(find.text('Legacy Routine 2'), findsOneWidget);

          await tester.tap(find.byType(FloatingActionButton));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(RoutineEditPage), findsOneWidget);
          expect(find.byType(PaywallPage), findsNothing);
        } finally {
          await _disposeWidgetTree(tester, db);
          if (legacy.tempDir.existsSync()) {
            legacy.tempDir.deleteSync(recursive: true);
          }
        }
      },
    );

    testWidgets(
      'RoutineEditPage Duplicate enforces free 2-routine limit and allows grandfathered v1.0.1 users',
      (tester) async {
        final db = RA_Database.forTesting(NativeDatabase.memory());
        final now = DateTime.now();
        await _seedRoutine(
          db,
          name: 'First Routine',
          nextTrigger: now.add(const Duration(hours: 1)),
        );
        await _seedRoutine(
          db,
          name: 'Second Routine',
          nextTrigger: now.add(const Duration(hours: 2)),
        );
        final first = (await db.getActiveRoutines()).first;
        await RA_PurchaseService.init();

        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                RA_DatabaseProvider.overrideWithValue(db),
                OfferingsProvider.overrideWith((ref) async => null),
              ],
              child: MaterialApp(
                theme: RA_AppTheme.themeData(),
                builder: (context, child) => RA_AppThemeScope(
                  mode: AppThemeModeEnum.Dark,
                  child: _ProRootListener(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
                home: RoutineEditPage(
                  dbPath: ':memory:',
                  existingRoutine: first,
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          final dupFinder = find.text('Duplicate');
          await tester.ensureVisible(dupFinder);
          await tester.pump();
          await tester.tap(dupFinder);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(PaywallPage), findsOneWidget);
          expect(await db.countLiveRoutines(), equals(2));
        } finally {
          await _disposeWidgetTree(tester, db);
        }

        // Now verify a v1.0.1 grandfathered upgrader with 2 routines bypasses
        // the cap on Duplicate and creates a 3rd routine.
        RA_PurchaseService.resetForTesting();
        SharedPreferences.setMockInitialValues({
          RA_PurchaseService.rcIsProCachedKey: false,
        });
        await RA_PurchaseService.init();

        final legacy = _createV17DatabaseFile(['Legacy One', 'Legacy Two']);
        final legacyDb = RA_Database.forTesting(
          NativeDatabase.opened(sqlite3.sqlite3.open(legacy.dbPath)),
        );
        try {
          expect(await legacyDb.isLegacyProGrandfathered(), isTrue);
          final legacyFirst = (await legacyDb.getActiveRoutines()).first;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                RA_DatabaseProvider.overrideWithValue(legacyDb),
                OfferingsProvider.overrideWith((ref) async => null),
              ],
              child: MaterialApp(
                theme: RA_AppTheme.themeData(),
                builder: (context, child) => RA_AppThemeScope(
                  mode: AppThemeModeEnum.Dark,
                  child: _ProRootListener(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
                home: RoutineEditPage(
                  dbPath: legacy.dbPath,
                  existingRoutine: legacyFirst,
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          final dupFinder = find.text('Duplicate');
          await tester.ensureVisible(dupFinder);
          await tester.pump();
          await tester.tap(dupFinder);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(PaywallPage), findsNothing);
          expect(await legacyDb.countLiveRoutines(), equals(3));
        } finally {
          await _disposeWidgetTree(tester, legacyDb);
          if (legacy.tempDir.existsSync()) {
            legacy.tempDir.deleteSync(recursive: true);
          }
        }
      },
    );

    testWidgets(
      'SettingsPage RA1 Import gates free users when import exceeds 2-routine cap but allows within cap',
      (tester) async {
        String encodeRoutines(List<String> names) {
          final payload = <String, Object?>{
            'version': 10,
            'routines': [
              for (final name in names)
                <String, Object?>{
                  'Name': name,
                  'IntervalSeconds': 3600,
                  'SnoozeSeconds': 300,
                },
            ],
          };
          return 'RA1:${base64Encode(utf8.encode(jsonEncode(payload)))}';
        }

        final db = RA_Database.forTesting(NativeDatabase.memory());
        final now = DateTime.now();
        await _seedRoutine(
          db,
          name: 'Existing Routine',
          nextTrigger: now.add(const Duration(hours: 1)),
        );
        await RA_PurchaseService.init();

        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                RA_DatabaseProvider.overrideWithValue(db),
                OfferingsProvider.overrideWith((ref) async => null),
              ],
              child: MaterialApp(
                theme: RA_AppTheme.themeData(),
                builder: (context, child) => RA_AppThemeScope(
                  mode: AppThemeModeEnum.Dark,
                  child: _ProRootListener(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
                home: const SettingsPage(dbPath: ':memory:'),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          final importFinder = find.text('Import Routines');
          final verticalScrollable = find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          );
          await tester.scrollUntilVisible(
            importFinder,
            300,
            scrollable: verticalScrollable.first,
          );
          await tester.ensureVisible(importFinder);
          await tester.pump();
          await tester.tap(importFinder);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          // 1 existing + 2 incoming = 3 > free limit (2) -> PaywallPage.
          await tester.enterText(
            find.byType(TextField),
            encodeRoutines(['Imported A', 'Imported B']),
          );
          await tester.tap(find.text('Import'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(PaywallPage), findsOneWidget);
          expect(await db.countLiveRoutines(), equals(1));

          // Close paywall, replace with 1 incoming routine (1 + 1 = 2 <= cap).
          await tester.tap(find.byTooltip('Close'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(PaywallPage), findsNothing);

          await tester.enterText(
            find.byType(TextField),
            encodeRoutines(['Allowed Import']),
          );
          await tester.tap(find.text('Import'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(await db.countLiveRoutines(), equals(2));
        } finally {
          await _disposeWidgetTree(tester, db);
        }
      },
    );
  });
}
