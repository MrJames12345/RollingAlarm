import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:rolling_alarm/components/common/app_theme_scope.dart';
import 'package:rolling_alarm/components/common/pro_badge.dart';
import 'package:rolling_alarm/components/routine/quick_templates_strip.dart';
import 'package:rolling_alarm/components/routine/routine_history_list.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/app_theme_mode.dart';
import 'package:rolling_alarm/enums/drift_compensation_type_code.dart';
import 'package:rolling_alarm/enums/log_action_type_code.dart';
import 'package:rolling_alarm/models/routine_template.dart';
import 'package:rolling_alarm/pages/home.dart';
import 'package:rolling_alarm/pages/logs.dart';
import 'package:rolling_alarm/pages/paywall.dart';
import 'package:rolling_alarm/pages/routine_edit.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/purchase.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockOfferings extends Mock implements Offerings {}

class _MockOffering extends Mock implements Offering {}

class _MockPackage extends Mock implements Package {}

class _MockStoreProduct extends Mock implements StoreProduct {}

Widget _wrapApp({
  required Widget home,
  List<Override> overrides = const [],
}) {
  RA_ColourStyles.apply(AppThemeModeEnum.Dark);
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: RA_AppTheme.themeData(),
      builder: (context, child) => RA_AppThemeScope(
        mode: AppThemeModeEnum.Dark,
        child: child ?? const SizedBox.shrink(),
      ),
      home: home,
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
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

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

    const homeWidgetChannel = MethodChannel('home_widget');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          homeWidgetChannel,
          (MethodCall call) async => true,
        );
  });

  setUp(() {
    RA_PurchaseService.resetForTesting();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    RA_PurchaseService.resetForTesting();
  });

  group('PaywallPage Widget Tests', () {
    testWidgets(
      'active Day-0 Founding offer shows countdown badge, founding price, strikethrough, and updates disclosure on tier selection',
      (tester) async {
        final recentFirstSeen = DateTime.now().subtract(
          const Duration(hours: 2),
        );
        SharedPreferences.setMockInitialValues({
          RA_PurchaseService.firstSeenEpochMsKey:
              recentFirstSeen.millisecondsSinceEpoch,
        });
        await RA_PurchaseService.init();

        final db = RA_Database.forTesting(NativeDatabase.memory());
        try {
          await tester.pumpWidget(
            _wrapApp(
              overrides: [
                RA_DatabaseProvider.overrideWithValue(db),
                OfferingsProvider.overrideWith((ref) async => null),
                IsProProvider.overrideWithValue(false),
              ],
              home: const PaywallPage(
                featureTrigger: 'Unlock unlimited rolling routines with Pro',
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          expect(find.text('Rolling Alarm Pro'), findsOneWidget);
          expect(
            find.text('Unlock unlimited rolling routines with Pro'),
            findsOneWidget,
          );
          expect(find.textContaining('DAY-1 OFFER'), findsOneWidget);
          expect(find.text(r'$19.99 AUD'), findsOneWidget);
          expect(find.text(r'$29.99 AUD'), findsOneWidget);
          expect(find.text(r'Unlock Lifetime · $19.99 AUD'), findsOneWidget);
          expect(
            find.textContaining('No recurring charges or auto-renewal.'),
            findsOneWidget,
          );

          // Select Annual Pro and verify CTA + Play auto-renewal disclosure update.
          await tester.ensureVisible(find.text('Annual Pro'));
          await tester.tap(find.text('Annual Pro'));
          await tester.pump();

          expect(find.text(r'Subscribe · $19.99 AUD/year'), findsOneWidget);
          expect(
            find.textContaining('Auto-renewing subscription billed at'),
            findsOneWidget,
          );
          expect(find.text('Restore Purchases'), findsOneWidget);
          expect(find.text('Manage Subscription'), findsOneWidget);
          expect(find.text('Terms of Use'), findsOneWidget);
          expect(find.text('Privacy Policy'), findsOneWidget);
        } finally {
          await _disposeWidgetTree(tester, db);
        }
      },
    );

    testWidgets(
      'expired Founding offer hides Day-1 badge, shows standard Lifetime price, and defaults to Annual Pro',
      (tester) async {
        final expiredFirstSeen = DateTime.now().subtract(
          const Duration(hours: 30),
        );
        SharedPreferences.setMockInitialValues({
          RA_PurchaseService.firstSeenEpochMsKey:
              expiredFirstSeen.millisecondsSinceEpoch,
        });
        await RA_PurchaseService.init();

        final db = RA_Database.forTesting(NativeDatabase.memory());
        try {
          await tester.pumpWidget(
            _wrapApp(
              overrides: [
                RA_DatabaseProvider.overrideWithValue(db),
                OfferingsProvider.overrideWith((ref) async => null),
                IsProProvider.overrideWithValue(false),
              ],
              home: const PaywallPage(),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          expect(find.textContaining('DAY-1 OFFER'), findsNothing);
          expect(
            find.text('ONE-TIME UNLOCK · NO SUBSCRIPTION'),
            findsOneWidget,
          );
          expect(find.text(r'$29.99 AUD'), findsOneWidget);
          expect(find.text(r'Subscribe · $19.99 AUD/year'), findsOneWidget);
        } finally {
          await _disposeWidgetTree(tester, db);
        }
      },
    );

    testWidgets(
      'renders localized RevenueCat Offerings pricing, computed savings badge, and Monthly disclosure',
      (tester) async {
        final recentFirstSeen = DateTime.now().subtract(
          const Duration(hours: 1),
        );
        SharedPreferences.setMockInitialValues({
          RA_PurchaseService.firstSeenEpochMsKey:
              recentFirstSeen.millisecondsSinceEpoch,
        });
        await RA_PurchaseService.init();

        Package makePkg({
          required String pkgId,
          required String sku,
          required String priceString,
          required double price,
          String? pricePerMonthString,
        }) {
          final product = _MockStoreProduct();
          when(() => product.identifier).thenReturn(sku);
          when(() => product.priceString).thenReturn(priceString);
          when(() => product.price).thenReturn(price);
          when(() => product.currencyCode).thenReturn('USD');
          when(() => product.pricePerMonthString).thenReturn(
            pricePerMonthString,
          );
          final pkg = _MockPackage();
          when(() => pkg.identifier).thenReturn(pkgId);
          when(() => pkg.storeProduct).thenReturn(product);
          return pkg;
        }

        final foundingPkg = makePkg(
          pkgId: 'founding',
          sku: RA_PurchaseService.foundingLifetimeSku,
          priceString: r'$14.99',
          price: 14.99,
        );
        final lifetimePkg = makePkg(
          pkgId: r'$rc_lifetime',
          sku: RA_PurchaseService.lifetimeSku,
          priceString: r'$24.99',
          price: 24.99,
        );
        final annualPkg = makePkg(
          pkgId: r'$rc_annual',
          sku: '${RA_PurchaseService.annualSku}:yearly-base',
          priceString: r'$14.99',
          price: 14.99,
          pricePerMonthString: r'$1.25',
        );
        final monthlyPkg = makePkg(
          pkgId: r'$rc_monthly',
          sku: '${RA_PurchaseService.monthlySku}:monthly-base',
          priceString: r'$2.49',
          price: 2.49,
        );

        final offering = _MockOffering();
        when(() => offering.identifier).thenReturn('default');
        when(() => offering.availablePackages).thenReturn([
          foundingPkg,
          lifetimePkg,
          annualPkg,
          monthlyPkg,
        ]);
        when(() => offering.lifetime).thenReturn(lifetimePkg);
        when(() => offering.annual).thenReturn(annualPkg);
        when(() => offering.monthly).thenReturn(monthlyPkg);

        final offerings = _MockOfferings();
        when(() => offerings.current).thenReturn(offering);
        when(() => offerings.all).thenReturn({'default': offering});

        final db = RA_Database.forTesting(NativeDatabase.memory());
        try {
          await tester.pumpWidget(
            _wrapApp(
              overrides: [
                RA_DatabaseProvider.overrideWithValue(db),
                OfferingsProvider.overrideWith((ref) async => offerings),
                IsProProvider.overrideWithValue(false),
              ],
              home: const PaywallPage(),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          // Founding price + strikethrough lifetime + dynamically calculated 50% badge.
          expect(find.text(r'Unlock Lifetime · $14.99'), findsOneWidget);
          expect(find.text(r'$24.99'), findsOneWidget);
          expect(find.text('SAVE 50%'), findsOneWidget);
          expect(find.text(r'Equivalent to $1.25/mo'), findsOneWidget);

          // Select Monthly Pro and verify CTA + monthly auto-renewal disclosure.
          await tester.ensureVisible(find.text('Monthly Pro'));
          await tester.tap(find.text('Monthly Pro'));
          await tester.pump();

          expect(find.text(r'Subscribe · $2.49/month'), findsOneWidget);
          expect(
            find.textContaining(
              r'Auto-renewing subscription billed at $2.49/month.',
            ),
            findsOneWidget,
          );
        } finally {
          await _disposeWidgetTree(tester, db);
        }
      },
    );

    testWidgets(
      'hydrates expired Founding offer when uninitialized, prevents duplicate PaywallPage.show stacking, and auto-pops on Pro unlock',
      (tester) async {
        final expiredFirstSeen = DateTime.now().subtract(
          const Duration(hours: 26),
        );
        SharedPreferences.setMockInitialValues({
          RA_PurchaseService.firstSeenEpochMsKey:
              expiredFirstSeen.millisecondsSinceEpoch,
        });
        expect(RA_PurchaseService.isInitialized, isFalse);

        final rcController = StreamController<bool>.broadcast();
        addTearDown(rcController.close);

        final db = RA_Database.forTesting(NativeDatabase.memory());
        late BuildContext hostContext;
        bool? firstResult;
        bool? secondResult;
        try {
          await tester.pumpWidget(
            _wrapApp(
              overrides: [
                RA_DatabaseProvider.overrideWithValue(db),
                OfferingsProvider.overrideWith((ref) async => null),
                RevenueCatProProvider.overrideWith((ref) => rcController.stream),
              ],
              home: Scaffold(
                body: Builder(
                  builder: (ctx) {
                    hostContext = ctx;
                    return const Center(child: Text('Host'));
                  },
                ),
              ),
            ),
          );
          await tester.pump();

          final f1 = PaywallPage.show(hostContext).then((v) => firstResult = v);
          // Concurrent second show must return false immediately without stacking.
          final f2 = PaywallPage.show(
            hostContext,
          ).then((v) => secondResult = v);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));

          expect(await f2, isFalse);
          expect(secondResult, isFalse);
          expect(find.byType(PaywallPage), findsOneWidget);
          expect(PaywallPage.isShowing, isTrue);

          // Async hydration discovered the expired timestamp and switched off Day-1.
          expect(find.textContaining('DAY-1 OFFER'), findsNothing);
          expect(find.text(r'Subscribe · $19.99 AUD/year'), findsOneWidget);

          // Simulate RevenueCat entitlement activating -> PaywallPage auto-pops true.
          rcController.add(true);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(await f1, isTrue);
          expect(firstResult, isTrue);
          expect(find.byType(PaywallPage), findsNothing);
          expect(PaywallPage.isShowing, isFalse);
        } finally {
          await _disposeWidgetTree(tester, db);
        }
      },
    );
  });

  group('Quick-Start Templates Unit & Widget Tests', () {
    test(
      'effectiveCompensation downgrades InitialRing to ActualDismissal for free users only',
      () {
        expect(RA_RoutineTemplates.focusHydration.usesProDriftMode, isTrue);
        expect(
          RA_RoutineTemplates.focusHydration.effectiveCompensation(
            isPro: false,
          ),
          equals(DriftCompensationTypeCodeEnum.ActualDismissal),
        );
        expect(
          RA_RoutineTemplates.focusHydration.effectiveCompensation(isPro: true),
          equals(DriftCompensationTypeCodeEnum.InitialRing),
        );
        expect(RA_RoutineTemplates.medication.usesProDriftMode, isFalse);
      },
    );

    testWidgets(
      'empty HomePage renders Quick Templates strip, shows PRO pill for free users, and prefills RoutineEditPage on tap',
      (tester) async {
        final db = RA_Database.forTesting(NativeDatabase.memory());
        try {
          await tester.pumpWidget(
            _wrapApp(
              overrides: [
                RA_DatabaseProvider.overrideWithValue(db),
                IsProProvider.overrideWithValue(false),
              ],
              home: const HomePage(dbPath: ':memory:'),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          expect(find.byType(RA_QuickTemplatesStrip), findsOneWidget);
          expect(find.text('Medication Cadence'), findsOneWidget);
          expect(find.text('Focus / Hydration Grid'), findsOneWidget);
          expect(find.byType(RA_ProBadge), findsOneWidget);

          await tester.tap(find.text('Medication Cadence'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(RoutineEditPage), findsOneWidget);
          expect(find.text('Medication'), findsOneWidget);
        } finally {
          await _disposeWidgetTree(tester, db);
        }
      },
    );

    testWidgets(
      'Quick Templates strip hides PRO badge when user is Pro',
      (tester) async {
        await tester.pumpWidget(
          _wrapApp(
            overrides: [IsProProvider.overrideWithValue(true)],
            home: Scaffold(
              body: RA_QuickTemplatesStrip(onSelect: (_) {}),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Focus / Hydration Grid'), findsOneWidget);
        expect(find.byType(RA_ProBadge), findsNothing);
      },
    );

    testWidgets(
      'RoutineEditPage free user selecting Pro template sees Actual Dismissal SnackBar and Fade-In / Classic Interval open PaywallPage',
      (tester) async {
        final db = RA_Database.forTesting(NativeDatabase.memory());
        try {
          await tester.pumpWidget(
            _wrapApp(
              overrides: [
                RA_DatabaseProvider.overrideWithValue(db),
                OfferingsProvider.overrideWith((ref) async => null),
                IsProProvider.overrideWithValue(false),
              ],
              home: const RoutineEditPage(dbPath: ':memory:'),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          await tester.tap(find.text('Focus / Hydration Grid'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          expect(find.text('Focus & Hydration'), findsOneWidget);
          expect(
            find.textContaining('Applied with Actual Dismissal.'),
            findsOneWidget,
          );

          // Tapping Fade in opens PaywallPage for free user.
          final fadeFinder = find.text('Fade in');
          await tester.ensureVisible(fadeFinder);
          await tester.pump();
          await tester.tap(fadeFinder);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(PaywallPage), findsOneWidget);
          expect(
            find.text('Unlock gentle alarm Fade-In with Pro'),
            findsOneWidget,
          );

          await tester.tap(find.byTooltip('Close'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(PaywallPage), findsNothing);

          // Tapping Classic Interval opens PaywallPage for free user.
          final classicFinder = find.text('Classic Interval');
          await tester.ensureVisible(classicFinder);
          await tester.pump();
          await tester.tap(classicFinder);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(PaywallPage), findsOneWidget);
          expect(
            find.text('Unlock Initial Ring Drift Compensation'),
            findsOneWidget,
          );
        } finally {
          await _disposeWidgetTree(tester, db);
          // Abrupt Navigator disposal while PaywallPage is open must reset
          // PaywallPage.isShowing so subsequent paywalls are never blocked.
          expect(PaywallPage.isShowing, isFalse);
        }
      },
    );
  });

  group('LogsPage Free 7-Day Cap & PDF Pro Gate Widget Tests', () {
    testWidgets(
      'free user sees only last 7 days with upgrade card and Share PDF opens PaywallPage; Pro sees older logs',
      (tester) async {
        final db = RA_Database.forTesting(NativeDatabase.memory());
        final now = DateTime.now();
        final recentRoutineId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Recent Dose'),
            IntervalSeconds: const Value(3600),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
          ),
        );
        final oldRoutineId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Old Archive Dose'),
            IntervalSeconds: const Value(3600),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
          ),
        );
        await db.insertLogEntry(
          LogEntriesCompanion(
            RoutineId: Value(recentRoutineId),
            Timestamp: Value(now.subtract(const Duration(hours: 2))),
            LogActionTypeCode: Value(LogActionTypeCodeEnum.Dismiss.index),
          ),
        );
        await db.insertLogEntry(
          LogEntriesCompanion(
            RoutineId: Value(oldRoutineId),
            Timestamp: Value(now.subtract(const Duration(days: 20))),
            LogActionTypeCode: Value(LogActionTypeCodeEnum.Dismiss.index),
          ),
        );

        try {
          // 1. Free user sees Recent Dose, NOT Old Archive Dose, and gets Paywall on PDF share.
          await tester.pumpWidget(
            _wrapApp(
              overrides: [
                RA_DatabaseProvider.overrideWithValue(db),
                OfferingsProvider.overrideWith((ref) async => null),
                IsProProvider.overrideWithValue(false),
              ],
              home: const LogsPage(dbPath: ':memory:'),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          expect(find.text('Recent Dose'), findsOneWidget);
          expect(find.text('Old Archive Dose'), findsNothing);
          expect(find.text('Showing last 7 days'), findsOneWidget);

          await tester.tap(find.byTooltip('Share PDF Report'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(PaywallPage), findsOneWidget);
          expect(
            find.text('Export printable PDF adherence logs with Pro'),
            findsOneWidget,
          );

          // 2. Pro user sees both recent and 20-day-old logs with no 7-day cap card.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(Duration.zero);
          await tester.pumpWidget(
            _wrapApp(
              overrides: [
                RA_DatabaseProvider.overrideWithValue(db),
                OfferingsProvider.overrideWith((ref) async => null),
                IsProProvider.overrideWithValue(true),
              ],
              home: const LogsPage(dbPath: ':memory:'),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          expect(find.text('Recent Dose'), findsOneWidget);
          expect(find.text('Old Archive Dose'), findsOneWidget);
          expect(find.text('Showing last 7 days'), findsNothing);
        } finally {
          await _disposeWidgetTree(tester, db);
        }
      },
    );

    testWidgets(
      'RA_RoutineHistoryList enforces Free 7-day cap with upgrade card opening PaywallPage and Pro sees older history',
      (tester) async {
        final db = RA_Database.forTesting(NativeDatabase.memory());
        final now = DateTime.now();
        final routineId = await db.insertRoutine(
          RoutinesCompanion(
            Name: const Value('Medication History'),
            IntervalSeconds: const Value(3600),
            DriftCompensationTypeCode: Value(
              DriftCompensationTypeCodeEnum.ActualDismissal.index,
            ),
          ),
        );
        await db.insertLogEntry(
          LogEntriesCompanion(
            RoutineId: Value(routineId),
            Timestamp: Value(now.subtract(const Duration(hours: 3))),
            LogActionTypeCode: Value(LogActionTypeCodeEnum.Dismiss.index),
          ),
        );
        await db.insertLogEntry(
          LogEntriesCompanion(
            RoutineId: Value(routineId),
            Timestamp: Value(now.subtract(const Duration(days: 20))),
            LogActionTypeCode: Value(LogActionTypeCodeEnum.Skip.index),
          ),
        );

        try {
          // 1. Free user sees recent Dismiss, NOT 20-day-old Skip, plus upgrade card.
          await tester.pumpWidget(
            _wrapApp(
              overrides: [
                RA_DatabaseProvider.overrideWithValue(db),
                OfferingsProvider.overrideWith((ref) async => null),
                IsProProvider.overrideWithValue(false),
              ],
              home: Scaffold(
                body: RA_RoutineHistoryList(
                  routineId: routineId,
                  dbPath: ':memory:',
                  routineName: 'Medication History',
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          expect(find.text('Dismiss'), findsOneWidget);
          expect(find.text('Skip'), findsNothing);
          expect(find.text('Showing last 7 days'), findsOneWidget);

          await tester.tap(find.text('Showing last 7 days'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(PaywallPage), findsOneWidget);
          expect(
            find.text('Unlock full 365-day adherence log history with Pro'),
            findsOneWidget,
          );

          // 2. Pro user sees both recent and 20-day-old history with no 7-day cap card.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(Duration.zero);
          await tester.pumpWidget(
            _wrapApp(
              overrides: [
                RA_DatabaseProvider.overrideWithValue(db),
                OfferingsProvider.overrideWith((ref) async => null),
                IsProProvider.overrideWithValue(true),
              ],
              home: Scaffold(
                body: RA_RoutineHistoryList(
                  routineId: routineId,
                  dbPath: ':memory:',
                  routineName: 'Medication History',
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          expect(find.text('Dismiss'), findsOneWidget);
          expect(find.text('Skip'), findsOneWidget);
          expect(find.text('Showing last 7 days'), findsNothing);
        } finally {
          await _disposeWidgetTree(tester, db);
        }
      },
    );
  });
}
