import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Selectable monetization tiers on [PaywallPage].
enum RA_PurchaseTier {
  foundingLifetime,
  lifetime,
  annual,
  monthly,
}

extension PurchaseTierDetails on RA_PurchaseTier {
  String get sku => switch (this) {
    RA_PurchaseTier.foundingLifetime => RA_PurchaseService.foundingLifetimeSku,
    RA_PurchaseTier.lifetime => RA_PurchaseService.lifetimeSku,
    RA_PurchaseTier.annual => RA_PurchaseService.annualSku,
    RA_PurchaseTier.monthly => RA_PurchaseService.monthlySku,
  };

  /// Offline / unconfigured fallback price display in AUD.
  String get fallbackPriceString => switch (this) {
    RA_PurchaseTier.foundingLifetime => r'$19.99 AUD',
    RA_PurchaseTier.lifetime => r'$29.99 AUD',
    RA_PurchaseTier.annual => r'$19.99 AUD',
    RA_PurchaseTier.monthly => r'$2.99 AUD',
  };

  bool get isSubscription => switch (this) {
    RA_PurchaseTier.foundingLifetime || RA_PurchaseTier.lifetime => false,
    RA_PurchaseTier.annual || RA_PurchaseTier.monthly => true,
  };

  ProductCategory get productCategory => isSubscription
      ? ProductCategory.subscription
      : ProductCategory.nonSubscription;
}

/// Terminal status of a purchase or restore call.
enum RA_PurchaseStatus {
  purchased,
  restored,
  cancelled,
  notConfigured,
  productUnavailable,
  noPurchasesFound,
  error,
}

/// Typed outcome returned by [RA_PurchaseService.purchaseTier] and
/// [RA_PurchaseService.restorePurchases].
class RA_PurchaseOutcome {
  final RA_PurchaseStatus status;
  final bool isPro;
  final String? message;

  const RA_PurchaseOutcome({
    required this.status,
    required this.isPro,
    this.message,
  });
}

/// Offline-first RevenueCat (`purchases_flutter` v11) monetization service.
///
/// Never blocks cold start or throws when `REVENUECAT_ANDROID_API_KEY` is blank
/// or when Google Play / network services are unavailable.
class RA_PurchaseService {
  RA_PurchaseService._();

  /// Passed at release build time via `--dart-define=REVENUECAT_ANDROID_API_KEY=...`.
  static const String apiKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_API_KEY',
  );

  // Entitlement & SKU identifiers
  static const String entitlementId = 'pro';
  static const String monthlySku = 'rolling_alarm_pro_monthly';
  static const String annualSku = 'rolling_alarm_pro_annual';
  static const String lifetimeSku = 'rolling_alarm_pro_lifetime';
  static const String foundingLifetimeSku =
      'rolling_alarm_pro_lifetime_founding';

  /// Free-tier maximum number of non-deleted routines.
  static const int freeRoutineLimit = 2;

  /// Free-tier log history window in days.
  static const int freeLogHistoryDays = 7;

  /// Day-0 founding lifetime discount duration from first launch.
  static const Duration foundingOfferWindow = Duration(hours: 24);

  // Legal & Google Play subscription management URLs
  static const String privacyPolicyUrl =
      'https://casellaweb.com.au/privacy/rolling-alarm';
  static const String termsOfUseUrl =
      'https://casellaweb.com.au/terms/rolling-alarm';
  static const String playSubscriptionsUrl =
      'https://play.google.com/store/account/subscriptions?package=com.casellaweb.rolling_alarm';

  // SharedPreferences & HomeWidget keys
  static const String firstSeenEpochMsKey = 'ra_first_seen_epoch_ms';
  static const String rcIsProCachedKey = 'ra_rc_is_pro_cached';
  static const String isProEffectiveKey = 'ra_is_pro_effective';
  static const String widgetIsProKey = 'ra_is_pro';

  static final StreamController<bool> _rcProController =
      StreamController<bool>.broadcast();

  static bool _initialized = false;
  static bool _configured = false;
  static bool _listenerRegistered = false;
  static bool _cachedRcPro = false;
  static bool _cachedLegacyPro = false;
  static int? _firstSeenEpochMs;
  static String? _latestManagementUrl;
  static bool? _queuedEffectivePro;
  static bool? _lastSyncedEffectivePro;
  static Future<void> _syncQueue = Future<void>.value();

  /// Optional test-only override for [IsProProvider].
  @visibleForTesting
  static bool? debugOverrideIsPro;

  /// Combines live/cached RevenueCat Pro and v1.0.1 grandfathering, honoring
  /// [debugOverrideIsPro] when set in tests.
  static bool resolveEffectivePro({
    required bool rcPro,
    required bool legacyPro,
  }) {
    final override = debugOverrideIsPro;
    if (override != null) return override;
    return rcPro || legacyPro;
  }

  static bool get isInitialized => _initialized;
  static bool get isApiKeyConfigured => apiKey.trim().isNotEmpty;
  static bool get isConfigured => _configured;
  static bool get cachedRcPro => _cachedRcPro;
  static bool get cachedLegacyPro => _cachedLegacyPro;

  /// Seeds or updates the in-memory v1.0.1 legacy grandfathering flag so
  /// [IsProProvider] and [SettingsPage] do not flash Free state while Drift's
  /// stream finishes its initial read, and so RevenueCat updates preserve
  /// combined effective Pro status when syncing to native preferences.
  static void setCachedLegacyPro(bool isLegacyPro) {
    _cachedLegacyPro = isLegacyPro;
  }

  /// Initializes local caches (`ra_first_seen_epoch_ms` and `ra_rc_is_pro_cached`)
  /// and configures RevenueCat when `REVENUECAT_ANDROID_API_KEY` is provided.
  ///
  /// Never blocks on network calls or throws in offline / emulator / test runs.
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final existingFirstSeen = prefs.getInt(firstSeenEpochMsKey);
      if (existingFirstSeen == null || existingFirstSeen <= 0) {
        _firstSeenEpochMs = nowMs;
        await prefs.setInt(firstSeenEpochMsKey, nowMs);
      } else {
        _firstSeenEpochMs = existingFirstSeen;
      }

      _cachedRcPro = prefs.getBool(rcIsProCachedKey) ?? false;
      _emitRcPro(_cachedRcPro);
    } catch (_) {
      // Missing plugin / test environment: fail soft.
      _firstSeenEpochMs ??= DateTime.now().millisecondsSinceEpoch;
    }

    _initialized = true;

    if (await _ensureConfigured()) {
      // Refresh entitlement asynchronously without blocking cold start.
      unawaited(refreshCustomerInfo());
    }
  }

  /// Lazily configures RevenueCat when `REVENUECAT_ANDROID_API_KEY` is set,
  /// allowing offline-at-launch sessions to recover once connectivity returns.
  static Future<bool> _ensureConfigured() async {
    if (!isApiKeyConfigured) return false;
    if (_configured) return true;
    try {
      final alreadyConfigured = await Purchases.isConfigured;
      if (!alreadyConfigured) {
        await Purchases.configure(PurchasesConfiguration(apiKey.trim()));
      }
      _configured = true;
      if (!_listenerRegistered) {
        Purchases.addCustomerInfoUpdateListener(_handleCustomerInfoUpdate);
        _listenerRegistered = true;
      }
      return true;
    } catch (_) {
      _configured = false;
      return false;
    }
  }

  /// Reactive stream of the RevenueCat `'pro'` entitlement (immediately seeded
  /// with the last cached offline value).
  static Stream<bool> watchRcPro() async* {
    if (!_initialized) {
      await _hydrateCachedRcPro();
    }
    yield _cachedRcPro;
    yield* _rcProController.stream;
  }

  static Future<void> _hydrateCachedRcPro() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getBool(rcIsProCachedKey) ?? false;
      _cachedRcPro = cached;
      final firstSeen = prefs.getInt(firstSeenEpochMsKey);
      if (firstSeen != null && firstSeen > 0) {
        _firstSeenEpochMs = firstSeen;
      }
    } catch (_) {}
  }

  /// Persists the combined effective Pro flag (`rcPro || legacyGrandfathered`)
  /// into both `SharedPreferences` (`ra_is_pro_effective`) and
  /// `HomeWidget` (`ra_is_pro`) so native `WidgetConfigActivity` can read it
  /// synchronously without opening Drift.
  ///
  /// Writes are serialized so out-of-order updates cannot overwrite newer state.
  static Future<void> syncEffectiveProStatus(bool isPro) {
    _queuedEffectivePro = isPro;
    final next = _syncQueue.catchError((Object _) {}).then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(isProEffectiveKey, isPro);
      } catch (_) {}
      try {
        await HomeWidget.saveWidgetData<bool>(widgetIsProKey, isPro);
      } catch (_) {}
      _lastSyncedEffectivePro = isPro;
    });
    _syncQueue = next;
    return next;
  }

  /// Deduplicated wrapper around [syncEffectiveProStatus] for provider updates.
  static Future<void> syncEffectiveProStatusIfChanged(bool isPro) async {
    if (_queuedEffectivePro == isPro && _lastSyncedEffectivePro == isPro) {
      return;
    }
    if (_queuedEffectivePro == isPro) {
      await _syncQueue;
      return;
    }
    await syncEffectiveProStatus(isPro);
  }

  /// Remaining time in the 24-hour Day-0 Founding Lifetime offer window.
  ///
  /// Persists `ra_first_seen_epoch_ms` on first call if not yet written.
  /// Returns [Duration.zero] once 24 hours have elapsed.
  static Future<Duration> foundingOfferRemaining({DateTime? now}) async {
    final reference = now ?? DateTime.now();
    var firstSeenMs = _firstSeenEpochMs;
    if (firstSeenMs == null || firstSeenMs <= 0) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final stored = prefs.getInt(firstSeenEpochMsKey);
        if (stored != null && stored > 0) {
          firstSeenMs = stored;
        } else {
          firstSeenMs = reference.millisecondsSinceEpoch;
          await prefs.setInt(firstSeenEpochMsKey, firstSeenMs);
        }
      } catch (_) {
        firstSeenMs = reference.millisecondsSinceEpoch;
      }
      _firstSeenEpochMs = firstSeenMs;
    }
    return _computeFoundingRemaining(firstSeenMs, reference);
  }

  /// Synchronous variant backed by the in-memory `firstSeenEpochMs` cache.
  static Duration foundingOfferRemainingSync({DateTime? now}) {
    final reference = now ?? DateTime.now();
    final firstSeenMs = _firstSeenEpochMs;
    if (firstSeenMs == null || firstSeenMs <= 0) {
      return foundingOfferWindow;
    }
    return _computeFoundingRemaining(firstSeenMs, reference);
  }

  static Duration _computeFoundingRemaining(int firstSeenMs, DateTime now) {
    final expiresAtMs = firstSeenMs + foundingOfferWindow.inMilliseconds;
    final remainingMs = expiresAtMs - now.millisecondsSinceEpoch;
    if (remainingMs <= 0) return Duration.zero;
    if (remainingMs > foundingOfferWindow.inMilliseconds) {
      return foundingOfferWindow;
    }
    return Duration(milliseconds: remainingMs);
  }

  /// Fetches the latest [CustomerInfo] from RevenueCat if configured, updating
  /// the offline cache and stream.
  static Future<bool> refreshCustomerInfo() async {
    if (!await _ensureConfigured()) return _cachedRcPro;
    try {
      final info = await Purchases.getCustomerInfo();
      await _applyCustomerInfo(info);
      return _cachedRcPro;
    } catch (_) {
      return _cachedRcPro;
    }
  }

  /// Fetches RevenueCat offerings, returning `null` cleanly when unconfigured
  /// or offline.
  static Future<Offerings?> getOfferings() async {
    if (!await _ensureConfigured()) return null;
    try {
      return await Purchases.getOfferings();
    } catch (_) {
      return null;
    }
  }

  /// Finds the RevenueCat [Package] matching [tier] inside [offerings].
  ///
  /// Handles Google Play Billing v5+ base-plan qualified identifiers
  /// (`<productId>:<basePlanId>`). Never falls back to standard lifetime when
  /// resolving [RA_PurchaseTier.foundingLifetime] so pricing stays exact.
  static Package? findPackageForTier(
    Offerings? offerings,
    RA_PurchaseTier tier,
  ) {
    if (offerings == null) return null;
    final orderedOfferings = <Offering>[
      if (offerings.current != null) offerings.current!,
      for (final offering in offerings.all.values)
        if (offering.identifier != offerings.current?.identifier) offering,
    ];

    // Pass 1: exact (or Play base-plan prefixed) StoreProduct identifier match.
    for (final offering in orderedOfferings) {
      for (final pkg in offering.availablePackages) {
        if (productMatchesSku(pkg.storeProduct.identifier, tier.sku)) {
          return pkg;
        }
      }
    }

    // Pass 2: package type fallback for standard tiers only.
    switch (tier) {
      case RA_PurchaseTier.foundingLifetime:
        for (final offering in orderedOfferings) {
          for (final pkg in offering.availablePackages) {
            if (pkg.identifier.toLowerCase().contains('founding')) {
              return pkg;
            }
          }
        }
        return null;
      case RA_PurchaseTier.lifetime:
        final candidate = offerings.current?.lifetime;
        if (candidate != null &&
            !productMatchesSku(
              candidate.storeProduct.identifier,
              foundingLifetimeSku,
            )) {
          return candidate;
        }
        return null;
      case RA_PurchaseTier.annual:
        return offerings.current?.annual;
      case RA_PurchaseTier.monthly:
        return offerings.current?.monthly;
    }
  }

  /// True when a Play Store product identifier matches [sku] directly or with
  /// a Google Play base-plan suffix (`<sku>:<basePlanId>`).
  static bool productMatchesSku(String storeProductId, String sku) {
    return storeProductId == sku || storeProductId.startsWith('$sku:');
  }

  /// Initiates a Google Play purchase for [tier] via `purchases_flutter` v11.
  static Future<RA_PurchaseOutcome> purchaseTier(
    RA_PurchaseTier tier, {
    Offerings? offerings,
  }) async {
    if (!await _ensureConfigured()) {
      return RA_PurchaseOutcome(
        status: RA_PurchaseStatus.notConfigured,
        isPro: _cachedRcPro,
        message:
            'Google Play billing is not configured in this build. Please install Rolling Alarm from Google Play.',
      );
    }

    try {
      final resolvedOfferings = offerings ?? await getOfferings();
      final pkg = findPackageForTier(resolvedOfferings, tier);

      PurchaseResult result;
      if (pkg != null) {
        result = await Purchases.purchase(PurchaseParams.package(pkg));
      } else {
        final products = await Purchases.getProducts(
          [tier.sku],
          productCategory: tier.productCategory,
        );
        if (products.isEmpty) {
          return RA_PurchaseOutcome(
            status: RA_PurchaseStatus.productUnavailable,
            isPro: _cachedRcPro,
            message:
                'This plan is temporarily unavailable from Google Play. Check your connection and try again.',
          );
        }
        result = await Purchases.purchase(
          PurchaseParams.storeProduct(products.first),
        );
      }

      await _applyCustomerInfo(result.customerInfo);
      if (_cachedRcPro) {
        return const RA_PurchaseOutcome(
          status: RA_PurchaseStatus.purchased,
          isPro: true,
          message: 'Welcome to Rolling Alarm Pro!',
        );
      }
      return const RA_PurchaseOutcome(
        status: RA_PurchaseStatus.error,
        isPro: false,
        message:
            'Purchase completed, but Pro entitlement is not active yet. Try Restore Purchases shortly.',
      );
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return RA_PurchaseOutcome(
          status: RA_PurchaseStatus.cancelled,
          isPro: _cachedRcPro,
        );
      }
      if (code == PurchasesErrorCode.productAlreadyPurchasedError) {
        await refreshCustomerInfo();
        if (_cachedRcPro) {
          return const RA_PurchaseOutcome(
            status: RA_PurchaseStatus.restored,
            isPro: true,
            message: 'Rolling Alarm Pro purchases restored.',
          );
        }
      }
      return RA_PurchaseOutcome(
        status: RA_PurchaseStatus.error,
        isPro: _cachedRcPro,
        message: e.message ?? 'Could not complete purchase. Please try again.',
      );
    } catch (_) {
      return RA_PurchaseOutcome(
        status: RA_PurchaseStatus.error,
        isPro: _cachedRcPro,
        message: 'Could not complete purchase. Please try again.',
      );
    }
  }

  /// Restores prior Google Play purchases linked to this Play account.
  static Future<RA_PurchaseOutcome> restorePurchases() async {
    if (!await _ensureConfigured()) {
      return RA_PurchaseOutcome(
        status: RA_PurchaseStatus.notConfigured,
        isPro: _cachedRcPro,
        message:
            'Google Play billing is not configured in this build. Please install Rolling Alarm from Google Play.',
      );
    }

    try {
      final info = await Purchases.restorePurchases();
      await _applyCustomerInfo(info);
      if (_cachedRcPro) {
        return const RA_PurchaseOutcome(
          status: RA_PurchaseStatus.restored,
          isPro: true,
          message: 'Rolling Alarm Pro purchases restored.',
        );
      }
      return const RA_PurchaseOutcome(
        status: RA_PurchaseStatus.noPurchasesFound,
        isPro: false,
        message:
            'No active Rolling Alarm Pro purchases were found for this Google Play account.',
      );
    } on PlatformException catch (e) {
      return RA_PurchaseOutcome(
        status: RA_PurchaseStatus.error,
        isPro: _cachedRcPro,
        message: e.message ?? 'Could not restore purchases. Please try again.',
      );
    } catch (_) {
      return RA_PurchaseOutcome(
        status: RA_PurchaseStatus.error,
        isPro: _cachedRcPro,
        message: 'Could not restore purchases. Please try again.',
      );
    }
  }

  /// Opens the Google Play Subscriptions management screen externally.
  static Future<bool> openManageSubscriptions() async {
    final managementUrl = _latestManagementUrl;
    if (managementUrl != null && managementUrl.isNotEmpty) {
      if (await openExternalUrl(managementUrl)) {
        return true;
      }
      if (managementUrl == playSubscriptionsUrl) {
        return false;
      }
    }
    return openExternalUrl(playSubscriptionsUrl);
  }

  /// Opens [url] in the user's external browser / Play Store app.
  static Future<bool> openExternalUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static void _handleCustomerInfoUpdate(CustomerInfo info) {
    unawaited(_applyCustomerInfo(info));
  }

  static Future<void> _applyCustomerInfo(CustomerInfo info) async {
    final active = info.entitlements.active.containsKey(entitlementId);
    _cachedRcPro = active;
    _latestManagementUrl = info.managementURL;
    _emitRcPro(active);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(rcIsProCachedKey, active);
    } catch (_) {}
    final effective = resolveEffectivePro(
      rcPro: active,
      legacyPro: _cachedLegacyPro,
    );
    await syncEffectiveProStatus(effective);
  }

  static void _emitRcPro(bool active) {
    if (!_rcProController.isClosed) {
      _rcProController.add(active);
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    if (_listenerRegistered) {
      try {
        Purchases.removeCustomerInfoUpdateListener(_handleCustomerInfoUpdate);
      } catch (_) {}
    }
    _initialized = false;
    _configured = false;
    _listenerRegistered = false;
    _cachedRcPro = false;
    _cachedLegacyPro = false;
    _firstSeenEpochMs = null;
    _latestManagementUrl = null;
    _queuedEffectivePro = null;
    _lastSyncedEffectivePro = null;
    _syncQueue = Future<void>.value();
    debugOverrideIsPro = null;
  }
}
