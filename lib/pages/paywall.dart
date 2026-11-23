import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/page_scaffold.dart';
import 'package:rolling_alarm/components/common/press_scale.dart';
import 'package:rolling_alarm/navigation/routes.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/purchase.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:rolling_alarm/utils.dart';

/// Google Play Subscriptions Policy-compliant paywall with a live 24-hour
/// Day-0 Founding Lifetime offer, localized RevenueCat pricing, and clean
/// offline/AUD fallbacks.
class PaywallPage extends ConsumerStatefulWidget {
  final String? featureTrigger;

  const PaywallPage({super.key, this.featureTrigger});

  static bool _isShowing = false;

  /// True while a [PaywallPage] route is currently presented via [show].
  static bool get isShowing => _isShowing;

  /// Presents [PaywallPage] and returns `true` if Pro was unlocked.
  ///
  /// Guards against rapid double-taps or concurrent native intents stacking
  /// duplicate paywall routes.
  static Future<bool> show(
    BuildContext context, {
    String? featureTrigger,
  }) async {
    if (_isShowing) return false;
    _isShowing = true;
    try {
      final result = await Navigator.of(context).push<bool>(
        RA_Routes.fade<bool>(PaywallPage(featureTrigger: featureTrigger)),
      );
      return result ?? false;
    } finally {
      _isShowing = false;
    }
  }

  @override
  ConsumerState<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends ConsumerState<PaywallPage> {
  late Duration _foundingRemaining;
  late RA_PurchaseTier _selectedTier;
  bool _userChangedSelection = false;
  bool _busy = false;
  bool _popped = false;
  Timer? _countdownTimer;

  bool get _isFoundingActive =>
      _foundingRemaining >= const Duration(seconds: 1);

  @override
  void initState() {
    super.initState();
    _foundingRemaining = RA_PurchaseService.foundingOfferRemainingSync();
    _selectedTier = _isFoundingActive
        ? RA_PurchaseTier.foundingLifetime
        : RA_PurchaseTier.annual;
    unawaited(_hydrateFoundingRemaining());
    if (!RA_PurchaseService.isInitialized || _isFoundingActive) {
      _countdownTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _tickFoundingCountdown(),
      );
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    PaywallPage._isShowing = false;
    super.dispose();
  }

  Future<void> _hydrateFoundingRemaining() async {
    final remaining = await RA_PurchaseService.foundingOfferRemaining();
    if (!mounted) return;
    setState(() {
      _foundingRemaining = remaining;
      if (!_isFoundingActive) {
        _countdownTimer?.cancel();
        _countdownTimer = null;
        if (_selectedTier == RA_PurchaseTier.foundingLifetime) {
          _selectedTier = _userChangedSelection
              ? RA_PurchaseTier.lifetime
              : RA_PurchaseTier.annual;
        }
      } else if (!_userChangedSelection) {
        _selectedTier = RA_PurchaseTier.foundingLifetime;
      }
    });
  }

  void _tickFoundingCountdown() {
    if (!mounted) return;
    final next = RA_PurchaseService.foundingOfferRemainingSync();
    if (next < const Duration(seconds: 1)) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      if (!_isFoundingActive && _foundingRemaining == Duration.zero) {
        return;
      }
    }
    setState(() {
      _foundingRemaining = next < const Duration(seconds: 1)
          ? Duration.zero
          : next;
      if (!_isFoundingActive &&
          _selectedTier == RA_PurchaseTier.foundingLifetime) {
        _selectedTier = _userChangedSelection
            ? RA_PurchaseTier.lifetime
            : RA_PurchaseTier.annual;
      }
    });
  }

  void _selectTier(RA_PurchaseTier tier) {
    if (_busy) return;
    setState(() {
      _selectedTier = tier;
      _userChangedSelection = true;
    });
  }

  void _popWithResult(bool unlocked) {
    if (_popped || !mounted) return;
    _popped = true;
    Navigator.of(context).pop(unlocked);
  }

  Future<void> _purchase(Offerings? offerings) async {
    if (_busy) return;
    if (_selectedTier == RA_PurchaseTier.foundingLifetime) {
      final liveRemaining = await RA_PurchaseService.foundingOfferRemaining();
      if (!mounted) return;
      if (liveRemaining < const Duration(seconds: 1)) {
        _tickFoundingCountdown();
        _showSnackBar(
          'The 24-hour Day-1 offer has ended. Review the updated plans below to continue.',
          isError: true,
        );
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final outcome = await RA_PurchaseService.purchaseTier(
        _selectedTier,
        offerings: offerings,
      );
      if (!mounted) return;
      if (outcome.isPro) {
        if (outcome.message != null) {
          _showSnackBar(outcome.message!, isError: false);
        }
        _popWithResult(true);
        return;
      }
      if (outcome.status != RA_PurchaseStatus.cancelled &&
          outcome.message != null) {
        _showSnackBar(outcome.message!, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final outcome = await RA_PurchaseService.restorePurchases();
      if (!mounted) return;
      if (outcome.message != null) {
        _showSnackBar(outcome.message!, isError: !outcome.isPro);
      }
      if (outcome.isPro) {
        _popWithResult(true);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openUrl(String url) async {
    final launched = await RA_PurchaseService.openExternalUrl(url);
    if (!launched && mounted) {
      _showSnackBar('Could not open link on this device.', isError: true);
    }
  }

  Future<void> _openManageSubscriptions() async {
    final launched = await RA_PurchaseService.openManageSubscriptions();
    if (!launched && mounted) {
      _showSnackBar(
        'Could not open Google Play Subscriptions on this device.',
        isError: true,
      );
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: RA_ColourStyles.surface,
        shape: RoundedRectangleBorder(
          borderRadius: RA_ShapeStyles.largeBorderRadius,
          side: BorderSide(color: RA_ShapeStyles.idleSurfaceBorder),
        ),
        content: Text(
          message,
          style: RA_TextStyles.smallFont.copyWith(
            color: isError
                ? RA_ColourStyles.softCoral
                : RA_ColourStyles.secondary,
          ),
        ),
      ),
    );
  }

  String? _resolveStrikethroughPrice({
    required StoreProduct? foundingProduct,
    required StoreProduct? lifetimeProduct,
  }) {
    if (foundingProduct != null && lifetimeProduct != null) {
      if (foundingProduct.currencyCode == lifetimeProduct.currencyCode &&
          lifetimeProduct.price > foundingProduct.price) {
        return lifetimeProduct.priceString;
      }
      return null;
    }
    if (foundingProduct == null && lifetimeProduct == null) {
      return RA_PurchaseTier.lifetime.fallbackPriceString;
    }
    return null;
  }

  String? _resolveAnnualSavingsBadge({
    required StoreProduct? annualProduct,
    required StoreProduct? monthlyProduct,
  }) {
    if (annualProduct != null && monthlyProduct != null) {
      if (annualProduct.currencyCode == monthlyProduct.currencyCode &&
          monthlyProduct.price > 0) {
        final yearlyFromMonthly = monthlyProduct.price * 12.0;
        if (yearlyFromMonthly > annualProduct.price) {
          final pct = ((1.0 - (annualProduct.price / yearlyFromMonthly)) * 100)
              .round();
          if (pct >= 5) return 'SAVE $pct%';
        }
      }
      return null;
    }
    if (annualProduct == null && monthlyProduct == null) {
      return 'SAVE 44%';
    }
    return null;
  }

  String _ctaLabel({
    required String lifetimePrice,
    required String annualPrice,
    required String monthlyPrice,
  }) {
    if (_busy) return 'Processing…';
    return switch (_selectedTier) {
      RA_PurchaseTier.foundingLifetime ||
      RA_PurchaseTier.lifetime => 'Unlock Lifetime · $lifetimePrice',
      RA_PurchaseTier.annual => 'Subscribe · $annualPrice/year',
      RA_PurchaseTier.monthly => 'Subscribe · $monthlyPrice/month',
    };
  }

  String _billingDisclosure({
    required String lifetimePrice,
    required String annualPrice,
    required String monthlyPrice,
  }) {
    return switch (_selectedTier) {
      RA_PurchaseTier.foundingLifetime || RA_PurchaseTier.lifetime =>
        'One-time payment of $lifetimePrice charged to your Google Play account at confirmation of purchase. No recurring charges or auto-renewal.',
      RA_PurchaseTier.annual =>
        'Auto-renewing subscription billed at $annualPrice/year. Charged to your Google Play account at confirmation and automatically renews unless canceled at least 24 hours before the end of the current period. Manage or cancel anytime in Google Play Subscriptions.',
      RA_PurchaseTier.monthly =>
        'Auto-renewing subscription billed at $monthlyPrice/month. Charged to your Google Play account at confirmation and automatically renews unless canceled at least 24 hours before the end of the current period. Manage or cancel anytime in Google Play Subscriptions.',
    };
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(AppThemeModeProvider);
    ref.listen<bool>(IsProProvider, (previous, next) {
      if (!_busy && next && previous != true) {
        _popWithResult(true);
      }
    });

    final offerings = ref.watch(OfferingsProvider).valueOrNull;
    final foundingProduct = RA_PurchaseService.findPackageForTier(
      offerings,
      RA_PurchaseTier.foundingLifetime,
    )?.storeProduct;
    final lifetimeProduct = RA_PurchaseService.findPackageForTier(
      offerings,
      RA_PurchaseTier.lifetime,
    )?.storeProduct;
    final annualProduct = RA_PurchaseService.findPackageForTier(
      offerings,
      RA_PurchaseTier.annual,
    )?.storeProduct;
    final monthlyProduct = RA_PurchaseService.findPackageForTier(
      offerings,
      RA_PurchaseTier.monthly,
    )?.storeProduct;

    final isFounding = _isFoundingActive;
    final activeLifetimeTier = isFounding
        ? RA_PurchaseTier.foundingLifetime
        : RA_PurchaseTier.lifetime;
    final activeLifetimePrice = isFounding
        ? (foundingProduct?.priceString ??
              RA_PurchaseTier.foundingLifetime.fallbackPriceString)
        : (lifetimeProduct?.priceString ??
              RA_PurchaseTier.lifetime.fallbackPriceString);
    final strikethroughLifetimePrice = isFounding
        ? _resolveStrikethroughPrice(
            foundingProduct: foundingProduct,
            lifetimeProduct: lifetimeProduct,
          )
        : null;

    final annualPrice =
        annualProduct?.priceString ??
        RA_PurchaseTier.annual.fallbackPriceString;
    final monthlyPrice =
        monthlyProduct?.priceString ??
        RA_PurchaseTier.monthly.fallbackPriceString;

    final annualMonthlySubtext = annualProduct?.pricePerMonthString != null
        ? 'Equivalent to ${annualProduct!.pricePerMonthString}/mo'
        : (annualProduct == null ? r'Equivalent to ~$1.67 AUD/mo' : null);

    final annualSavingsBadge = _resolveAnnualSavingsBadge(
      annualProduct: annualProduct,
      monthlyProduct: monthlyProduct,
    );

    final trigger = widget.featureTrigger?.trim();
    final hasTrigger = trigger != null && trigger.isNotEmpty;

    return PopScope(
      canPop: !_busy,
      child: RA_PageScaffold(
        title: '',
        automaticallyImplyLeading: false,
        actions: [
          RA_AppBarIconButton(
            icon: Icons.close,
            tooltip: 'Close',
            onPressed: () {
              if (!_busy) _popWithResult(false);
            },
          ),
        ],
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            RA_ShapeStyles.space16,
            0,
            RA_ShapeStyles.space16,
            RA_ShapeStyles.space32,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
            if (hasTrigger) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: _TriggerPill(text: trigger),
              ),
              const SizedBox(height: RA_ShapeStyles.space16),
            ],
            Text(
              'Rolling Alarm Pro',
              style: RA_TextStyles.largeFont.copyWith(fontSize: 28),
            ),
            const SizedBox(height: RA_ShapeStyles.space8),
            Text(
              'Built for medication cadences, shift rosters, and zero-drift routines — 100% offline privacy.',
              style: RA_TextStyles.smallFont.copyWith(
                color: RA_ColourStyles.mutedPrimary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: RA_ShapeStyles.space24),
            const _ProFeatureList(),
            const SizedBox(height: RA_ShapeStyles.space24),
            _TierCard(
              title: 'Lifetime Unlock',
              badgeText: isFounding
                  ? 'DAY-1 OFFER · ENDS IN ${RA_Utils.formatCountdown(_foundingRemaining)}'
                  : 'ONE-TIME UNLOCK · NO SUBSCRIPTION',
              badgeColor: isFounding
                  ? RA_ColourStyles.softCoral
                  : RA_ColourStyles.secondary,
              prominentPrice: activeLifetimePrice,
              strikethroughPrice: strikethroughLifetimePrice,
              subtext: 'One-time payment · Own Pro forever',
              selected: _selectedTier == activeLifetimeTier,
              accentColor: isFounding
                  ? RA_ColourStyles.softCoral
                  : RA_ColourStyles.secondary,
              onTap: () => _selectTier(activeLifetimeTier),
            ),
            const SizedBox(height: RA_ShapeStyles.space8),
            _TierCard(
              title: 'Annual Pro',
              badgeText: annualSavingsBadge,
              badgeColor: RA_ColourStyles.secondary,
              prominentPrice: '$annualPrice/year',
              subtext: annualMonthlySubtext ?? 'Billed once per year',
              selected: _selectedTier == RA_PurchaseTier.annual,
              accentColor: RA_ColourStyles.secondary,
              onTap: () => _selectTier(RA_PurchaseTier.annual),
            ),
            const SizedBox(height: RA_ShapeStyles.space8),
            _TierCard(
              title: 'Monthly Pro',
              prominentPrice: '$monthlyPrice/month',
              subtext: 'Flexible monthly plan · Cancel anytime',
              selected: _selectedTier == RA_PurchaseTier.monthly,
              accentColor: RA_ColourStyles.secondary,
              onTap: () => _selectTier(RA_PurchaseTier.monthly),
            ),
            const SizedBox(height: RA_ShapeStyles.space24),
            RA_Button(
              text: _ctaLabel(
                lifetimePrice: activeLifetimePrice,
                annualPrice: annualPrice,
                monthlyPrice: monthlyPrice,
              ),
              backgroundColor:
                  _selectedTier == RA_PurchaseTier.foundingLifetime
                  ? RA_ColourStyles.softCoral
                  : RA_ColourStyles.secondary,
              foregroundColor: RA_ColourStyles.onAccent,
              shadowColor:
                  (_selectedTier == RA_PurchaseTier.foundingLifetime
                          ? RA_ColourStyles.softCoral
                          : RA_ColourStyles.secondary)
                      .withValues(alpha: 0.35),
              onClick: _busy ? null : () => unawaited(_purchase(offerings)),
            ),
            const SizedBox(height: RA_ShapeStyles.space16),
            Text(
              _billingDisclosure(
                lifetimePrice: activeLifetimePrice,
                annualPrice: annualPrice,
                monthlyPrice: monthlyPrice,
              ),
              textAlign: TextAlign.center,
              style: RA_TextStyles.tinyFont.copyWith(
                color: RA_ColourStyles.mutedPrimary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: RA_ShapeStyles.space16),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: RA_ShapeStyles.space8,
              runSpacing: 0,
              children: [
                _FooterLinkButton(
                  label: 'Restore Purchases',
                  onTap: _busy ? null : () => unawaited(_restore()),
                ),
                _FooterLinkButton(
                  label: 'Manage Subscription',
                  onTap: () => unawaited(_openManageSubscriptions()),
                ),
                _FooterLinkButton(
                  label: 'Terms of Use',
                  onTap: () =>
                      unawaited(_openUrl(RA_PurchaseService.termsOfUseUrl)),
                ),
                _FooterLinkButton(
                  label: 'Privacy Policy',
                  onTap: () =>
                      unawaited(_openUrl(RA_PurchaseService.privacyPolicyUrl)),
                ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _TriggerPill extends StatelessWidget {
  final String text;

  const _TriggerPill({required this.text});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RA_ColourStyles.secondary.withValues(alpha: 0.14),
        borderRadius: RA_ShapeStyles.largeBorderRadius,
        border: Border.all(
          color: RA_ColourStyles.secondary.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RA_ShapeStyles.space16,
          vertical: RA_ShapeStyles.space8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_open_rounded,
              size: 16,
              color: RA_ColourStyles.readableAccent(RA_ColourStyles.secondary),
            ),
            const SizedBox(width: RA_ShapeStyles.space8),
            Flexible(
              child: Text(
                text,
                style: RA_TextStyles.tinyFont.copyWith(
                  color: RA_ColourStyles.readableAccent(
                    RA_ColourStyles.secondary,
                  ),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProFeatureList extends StatelessWidget {
  const _ProFeatureList();

  static const List<(IconData, String)> _features = [
    (Icons.all_inclusive_rounded, 'Unlimited Rolling Routines'),
    (Icons.grid_on_rounded, 'Initial Ring Grid & Extra Daily Caps'),
    (
      Icons.graphic_eq_rounded,
      'Custom Audio + Gentle Fade-In + Volume-Key Actions',
    ),
    (Icons.widgets_outlined, 'Unlimited Home Screen Widgets'),
    (
      Icons.picture_as_pdf_outlined,
      'Full Log History + Printable PDF Reports + RA1: Backups',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: RA_ShapeStyles.elevatedSurface(),
      child: Padding(
        padding: const EdgeInsets.all(RA_ShapeStyles.space16),
        child: Column(
          children: [
            for (var i = 0; i < _features.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      _features[i].$1,
                      size: 18,
                      color: RA_ColourStyles.secondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _features[i].$2,
                      style: RA_TextStyles.tinyFont.copyWith(height: 1.35),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  final String title;
  final String? badgeText;
  final Color? badgeColor;
  final String prominentPrice;
  final String? strikethroughPrice;
  final String subtext;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  const _TierCard({
    required this.title,
    this.badgeText,
    this.badgeColor,
    required this.prominentPrice,
    this.strikethroughPrice,
    required this.subtext,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final badgeAccent = badgeColor ?? accentColor;
    final glow = selected
        ? (accentColor == RA_ColourStyles.softCoral
              ? RA_ShapeStyles.softCoralGlow
              : RA_ShapeStyles.tealGlow)
        : null;

    return RA_PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            RA_Haptics.heavyUnawaited();
            onTap();
          },
          borderRadius: RA_ShapeStyles.largeBorderRadius,
          splashColor: accentColor.withValues(alpha: 0.16),
          highlightColor: accentColor.withValues(alpha: 0.08),
          child: AnimatedContainer(
            duration: RA_ShapeStyles.stateTransitionDuration,
            curve: Curves.easeOut,
            decoration: RA_ShapeStyles.elevatedSurface(
              fill: selected
                  ? Color.alphaBlend(
                      accentColor.withValues(alpha: 0.09),
                      RA_ColourStyles.surface,
                    )
                  : RA_ColourStyles.surface,
              borderColor: selected
                  ? accentColor.withValues(alpha: 0.65)
                  : null,
              borderWidth: selected ? 1.5 : 1,
              boxShadow: glow,
            ),
            child: Padding(
              padding: const EdgeInsets.all(RA_ShapeStyles.space16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (badgeText != null) ...[
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: badgeAccent.withValues(alpha: 0.16),
                        borderRadius: RA_ShapeStyles.tinyBorderRadius,
                        border: Border.all(
                          color: badgeAccent.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: RA_ShapeStyles.space8,
                          vertical: 3,
                        ),
                        child: Text(
                          badgeText!,
                          style: RA_TextStyles.tinyFont.copyWith(
                            color: RA_ColourStyles.readableAccent(badgeAccent),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: RA_ShapeStyles.space8),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 22,
                          color: selected
                              ? accentColor
                              : RA_ColourStyles.mutedPrimary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: RA_TextStyles.smallFont.copyWith(
                                fontWeight: FontWeight.w700,
                                color: selected
                                    ? RA_ColourStyles.readableAccent(
                                        accentColor,
                                      )
                                    : RA_ColourStyles.primary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: RA_ShapeStyles.space8,
                              runSpacing: 2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  prominentPrice,
                                  style: RA_TextStyles.mediumFont.copyWith(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: selected
                                        ? RA_ColourStyles.readableAccent(
                                            accentColor,
                                          )
                                        : RA_ColourStyles.primary,
                                  ),
                                ),
                                if (strikethroughPrice != null)
                                  Text(
                                    strikethroughPrice!,
                                    style: RA_TextStyles.tinyFont.copyWith(
                                      color: RA_ColourStyles.mutedPrimary,
                                      fontSize: 13,
                                      decoration: TextDecoration.lineThrough,
                                      decorationColor:
                                          RA_ColourStyles.mutedPrimary,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtext,
                              style: RA_TextStyles.tinyFont.copyWith(
                                color: RA_ColourStyles.mutedPrimary,
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterLinkButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _FooterLinkButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap == null
          ? null
          : () {
              RA_Haptics.heavyUnawaited();
              onTap!();
            },
      style: TextButton.styleFrom(
        minimumSize: const Size(
          RA_ShapeStyles.minTouchTarget,
          RA_ShapeStyles.minTouchTarget,
        ),
        padding: const EdgeInsets.symmetric(horizontal: RA_ShapeStyles.space8),
      ),
      child: Text(
        label,
        style: RA_TextStyles.tinyFont.copyWith(
          color: RA_ColourStyles.mutedPrimary,
          fontSize: 12,
          decoration: TextDecoration.underline,
          decorationColor: RA_ColourStyles.mutedPrimary,
        ),
      ),
    );
  }
}
