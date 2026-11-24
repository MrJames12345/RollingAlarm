import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rolling_alarm/components/common/button.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/styles.dart';

/// Manufacturer-specific copy shown in [RA_OemBatteryGuideSheet].
class RA_OemBatteryGuideContent {
  final String brandBadge;
  final String title;
  final List<String> bullets;

  const RA_OemBatteryGuideContent({
    required this.brandBadge,
    required this.title,
    required this.bullets,
  });

  /// Resolves tailored OEM instructions for `android.os.Build.MANUFACTURER`.
  static RA_OemBatteryGuideContent forManufacturer(String rawManufacturer) {
    final m = rawManufacturer.trim().toLowerCase();
    if (m.contains('samsung')) {
      return const RA_OemBatteryGuideContent(
        brandBadge: 'Samsung · One UI',
        title: 'Keep Samsung Alarms Reliable',
        bullets: [
          'Samsung One UI Sleeping & Deep Sleeping Apps can pause overnight alarm receivers when the screen stays off.',
          'Tap below and choose Unrestricted battery (Settings -> Apps -> Rolling Alarm -> Battery -> Unrestricted) so alarms fire on the exact second.',
        ],
      );
    }
    if (m.contains('xiaomi') || m.contains('poco') || m.contains('redmi')) {
      return const RA_OemBatteryGuideContent(
        brandBadge: 'Xiaomi · HyperOS / MIUI',
        title: 'Keep Xiaomi Alarms Reliable',
        bullets: [
          'Xiaomi HyperOS / MIUI Battery Saver routinely terminates background alarm services overnight to save power.',
          'Tap below and allow Unrestricted battery (No restrictions in Battery Saver, plus Autostart if listed) so lock-screen alarms never get silenced.',
        ],
      );
    }
    if (m.contains('oppo') || m.contains('realme') || m.contains('oneplus')) {
      return const RA_OemBatteryGuideContent(
        brandBadge: 'Oppo / Realme / OnePlus',
        title: 'Keep Background Alarms Reliable',
        bullets: [
          'ColorOS and OxygenOS auto-freeze background apps overnight, which can delay or silence scheduled exact alarms.',
          'Tap below to allow Unrestricted battery (and enable Allow background activity in App Battery Management) for reliable overnight rings.',
        ],
      );
    }
    if (m.contains('vivo') || m.contains('iqoo')) {
      return const RA_OemBatteryGuideContent(
        brandBadge: 'Vivo · Funtouch / OriginOS',
        title: 'Keep Vivo Alarms Reliable',
        bullets: [
          'Vivo background power limits can stop scheduled alarm receivers while your screen is locked overnight.',
          'Tap below to allow Unrestricted battery (Allow high background power consumption) so every rolling alarm wakes your phone on time.',
        ],
      );
    }
    return const RA_OemBatteryGuideContent(
      brandBadge: 'Android Battery Reliability',
      title: 'Keep Overnight Alarms Reliable',
      bullets: [
        'Aggressive Android battery savers and Doze mode can delay or silence background alarm services overnight.',
        'Allowing Unrestricted battery ensures Rolling Alarm wakes your screen and rings on the exact second.',
      ],
    );
  }
}

/// Themed modal bottom sheet explaining OEM battery optimization killers and
/// providing a 1-tap path to `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.
class RA_OemBatteryGuideSheet extends StatefulWidget {
  final String manufacturer;
  final Future<void> Function()? onAllowUnrestricted;

  const RA_OemBatteryGuideSheet({
    super.key,
    required this.manufacturer,
    this.onAllowUnrestricted,
  });

  /// Presents [RA_OemBatteryGuideSheet] as a themed modal bottom sheet.
  static Future<bool?> show(
    BuildContext context, {
    required String manufacturer,
    Future<void> Function()? onAllowUnrestricted,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: RA_ColourStyles.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => RA_OemBatteryGuideSheet(
        manufacturer: manufacturer,
        onAllowUnrestricted: onAllowUnrestricted,
      ),
    );
  }

  @override
  State<RA_OemBatteryGuideSheet> createState() =>
      _RA_OemBatteryGuideSheetState();
}

class _RA_OemBatteryGuideSheetState extends State<RA_OemBatteryGuideSheet> {
  bool _busy = false;

  Future<void> _handleAllow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final handler = widget.onAllowUnrestricted;
      if (handler != null) {
        await handler();
      } else {
        await RA_AlarmService.requestIgnoreBatteryOptimizations();
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = RA_OemBatteryGuideContent.forManufacturer(
      widget.manufacturer,
    );

    return SafeArea(
      maintainBottomViewPadding: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          RA_ShapeStyles.space24,
          RA_ShapeStyles.space16,
          RA_ShapeStyles.space24,
          RA_ShapeStyles.space24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: RA_ColourStyles.faintPrimary,
                  borderRadius: RA_ShapeStyles.microBorderRadius,
                ),
              ),
            ),
            const SizedBox(height: RA_ShapeStyles.space16),
            Align(
              alignment: Alignment.centerLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: RA_ColourStyles.pauseOchre.withValues(alpha: 0.16),
                  borderRadius: RA_ShapeStyles.tinyBorderRadius,
                  border: Border.all(
                    color: RA_ColourStyles.pauseOchre.withValues(alpha: 0.45),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RA_ShapeStyles.space8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.battery_charging_full_rounded,
                        size: 16,
                        color: RA_ColourStyles.readableAccent(
                          RA_ColourStyles.pauseOchre,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          content.brandBadge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: RA_TextStyles.tinyFont.copyWith(
                            color: RA_ColourStyles.readableAccent(
                              RA_ColourStyles.pauseOchre,
                            ),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: RA_ShapeStyles.space16),
            Text(content.title, style: RA_TextStyles.largeFont),
            const SizedBox(height: RA_ShapeStyles.space16),
            for (var i = 0; i < content.bullets.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                      color: RA_ColourStyles.secondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      content.bullets[i],
                      style: RA_TextStyles.tinyFont.copyWith(
                        color: RA_ColourStyles.mutedPrimary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: RA_ShapeStyles.space24),
            RA_Button(
              text: 'Allow Unrestricted Battery',
              onClick: _busy ? null : () => unawaited(_handleAllow()),
            ),
            const SizedBox(height: RA_ShapeStyles.space8),
            Center(
              child: RA_DialogButton('Later', () {
                if (!_busy) Navigator.of(context).pop(false);
              }),
            ),
          ],
        ),
      ),
    );
  }
}
