import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rolling_alarm/components/common/fitted_text.dart';
import 'package:rolling_alarm/components/common/form_section.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/import_export_dialogs.dart';
import 'package:rolling_alarm/components/common/page_scaffold.dart';
import 'package:rolling_alarm/components/common/press_scale.dart';
import 'package:rolling_alarm/components/common/pro_badge.dart';
import 'package:rolling_alarm/components/field/radio_group.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/alarm_side_button_action.dart';
import 'package:rolling_alarm/enums/alarm_snooze_dismiss_layout.dart';
import 'package:rolling_alarm/enums/app_theme_mode.dart';
import 'package:rolling_alarm/enums/routine_swipe_action.dart';
import 'package:rolling_alarm/pages/paywall.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/services/alarm.dart';
import 'package:rolling_alarm/services/export.dart';
import 'package:rolling_alarm/services/notification.dart';
import 'package:rolling_alarm/services/permissions.dart';
import 'package:rolling_alarm/services/purchase.dart';
import 'package:rolling_alarm/services/review.dart';
import 'package:rolling_alarm/services/widget.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:rolling_alarm/utils.dart';

class SettingsPage extends ConsumerStatefulWidget {
  final String dbPath;

  const SettingsPage({super.key, required this.dbPath});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage>
    with WidgetsBindingObserver {
  static const String _appVersion = '1.1.0';

  RA_AlarmPermissionStatus? _reliabilityStatus;
  bool _restoringPurchases = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshReliabilityStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshReliabilityStatus());
    }
  }

  Future<void> _refreshReliabilityStatus() async {
    final status = await RA_PermissionService.getStatus();
    if (!mounted) return;
    setState(() => _reliabilityStatus = status);
  }

  Future<void> _requestBatteryExemption() async {
    await RA_AlarmService.requestIgnoreBatteryOptimizations();
    await _refreshReliabilityStatus();
  }

  Future<void> _openOemBatteryGuide() async {
    await RA_PermissionService.showOemBatteryGuide(context);
    await _refreshReliabilityStatus();
  }

  Future<void> _requestFullScreenIntent() async {
    await RA_NotificationService.requestFullScreenIntentPermission();
    await _refreshReliabilityStatus();
  }

  Future<void> _requestDisplayOverApps() async {
    await RA_tryAsync(() => Permission.systemAlertWindow.request());
    await _refreshReliabilityStatus();
  }

  Future<void> _restorePurchases() async {
    if (_restoringPurchases) return;
    setState(() => _restoringPurchases = true);
    try {
      final outcome = await RA_PurchaseService.restorePurchases();
      if (!mounted) return;
      if (outcome.message != null) {
        _showStatusSnackBar(outcome.message!, isError: !outcome.isPro);
      }
    } finally {
      if (mounted) {
        setState(() => _restoringPurchases = false);
      }
    }
  }

  Future<void> _openManageSubscriptions() async {
    final launched = await RA_PurchaseService.openManageSubscriptions();
    if (!launched && mounted) {
      _showStatusSnackBar(
        'Could not open Google Play Subscriptions on this device.',
        isError: true,
      );
    }
  }

  Future<void> _openLegalUrl(String url) async {
    final launched = await RA_PurchaseService.openExternalUrl(url);
    if (!launched && mounted) {
      _showStatusSnackBar('Could not open link on this device.', isError: true);
    }
  }

  void _showStatusSnackBar(String message, {required bool isError}) {
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

  @override
  Widget build(BuildContext context) {
    final isPro = ref.watch(IsProProvider);
    final isLegacyPro =
        ref.watch(LegacyProGrandfatheredProvider).valueOrNull ??
        RA_PurchaseService.cachedLegacyPro;
    final isRcPro =
        ref.watch(RevenueCatProProvider).valueOrNull ??
        RA_PurchaseService.cachedRcPro;
    final layout =
        ref.watch(AlarmSnoozeDismissLayoutProvider).valueOrNull ??
        AlarmSnoozeDismissLayoutEnum.Sliders;
    final themeMode =
        ref.watch(AppThemeModeProvider).valueOrNull ?? AppThemeModeEnum.Dark;
    final sideButtons =
        ref.watch(AlarmSideButtonsProvider).valueOrNull ??
        const AlarmSideButtonsSettings();
    final swipeActions =
        ref.watch(RoutineSwipeActionsProvider).valueOrNull ??
        const RoutineSwipeActionsSettings();
    final cardButtons =
        ref.watch(RoutineCardButtonsProvider).valueOrNull ??
        const RoutineCardButtonsSettings();

    return RA_PageScaffold(
      title: 'Settings',
      body: ListView(
        padding: RA_ShapeStyles.bodyPadding,
        children: [
          RA_FormSection(
            label: 'Rolling Alarm Pro',
            child: isPro
                ? _ProUnlockedSection(
                    isLegacyEarlySupporter: isLegacyPro && !isRcPro,
                    restoring: _restoringPurchases,
                    onManageSubscription: () =>
                        unawaited(_openManageSubscriptions()),
                    onRestorePurchases: () => unawaited(_restorePurchases()),
                  )
                : _ProUpgradeSection(
                    restoring: _restoringPurchases,
                    onUpgrade: () => unawaited(
                      PaywallPage.show(
                        context,
                        featureTrigger: 'Unlock all Rolling Alarm Pro features',
                      ),
                    ),
                    onRestorePurchases: () => unawaited(_restorePurchases()),
                  ),
          ),
          RA_FormSection(
            label: 'Theme',
            child: RA_RadioGroup<AppThemeModeEnum>(
              groupValue: themeMode,
              onChanged: (v) =>
                  unawaited(ref.read(AppThemeModeProvider.notifier).setMode(v)),
              options: const [
                RA_RadioOption(value: AppThemeModeEnum.Dark, title: 'Dark'),
                RA_RadioOption(value: AppThemeModeEnum.Light, title: 'Light'),
              ],
            ),
          ),
          RA_FormSection(
            label: 'Alarm Layout',
            child: RA_RadioGroup<AlarmSnoozeDismissLayoutEnum>(
              groupValue: layout,
              onChanged: (v) => unawaited(
                ref
                    .read(AlarmSnoozeDismissLayoutProvider.notifier)
                    .setLayout(v),
              ),
              options: const [
                RA_RadioOption(
                  value: AlarmSnoozeDismissLayoutEnum.Sliders,
                  title: 'Sliders',
                ),
                RA_RadioOption(
                  value: AlarmSnoozeDismissLayoutEnum.Buttons,
                  title: 'Buttons',
                ),
              ],
            ),
          ),
          RA_FormSection(
            label: 'Side Buttons',
            labelTrailing: !isPro ? const RA_ProBadge() : null,
            child: _SideButtonsTileRow(
              settings: sideButtons,
              onSelect: (button) => unawaited(
                _pickSideButtonAction(context, ref, button, sideButtons),
              ),
            ),
          ),
          RA_FormSection(
            label: 'Swipe Actions',
            child: _SwipeActionsTileRow(
              settings: swipeActions,
              onSelect: (direction) => unawaited(
                _pickSwipeAction(
                  context,
                  ref,
                  direction,
                  swipeActions,
                  isPro: isPro,
                ),
              ),
            ),
          ),
          RA_FormSection(
            label: 'Card Buttons',
            child: _CardButtonsTileRow(
              settings: cardButtons,
              onSelect: (position) => unawaited(
                _pickCardButtonAction(
                  context,
                  ref,
                  position,
                  cardButtons,
                  isPro: isPro,
                ),
              ),
            ),
          ),
          RA_FormSection(
            label: 'Alarm Reliability',
            child: Column(
              children: [
                _ReliabilityActionTile(
                  icon: Icons.battery_charging_full,
                  title: 'Unrestricted Battery (Samsung / Xiaomi / Oppo)',
                  subtitle:
                      'Prevents aggressive battery savers from stopping alarms in the background.',
                  isActive:
                      _reliabilityStatus?.unrestrictedBatteryGranted == true,
                  onTap: () => unawaited(_requestBatteryExemption()),
                ),
                const SizedBox(height: RA_ShapeStyles.space8),
                _ReliabilityActionTile(
                  icon: Icons.fullscreen,
                  title: 'Lock-Screen Full-Screen Alert',
                  subtitle:
                      'Allows alarms to wake the display and appear over the lock screen.',
                  isActive: _reliabilityStatus?.fullScreenIntentGranted == true,
                  onTap: () => unawaited(_requestFullScreenIntent()),
                ),
                const SizedBox(height: RA_ShapeStyles.space8),
                _ReliabilityActionTile(
                  icon: Icons.layers_outlined,
                  title: 'Display Over Active Apps Fallback',
                  subtitle:
                      'Fallback to show alarm controls over other open apps when restricted.',
                  isActive: _reliabilityStatus?.displayOverAppsGranted == true,
                  onTap: () => unawaited(_requestDisplayOverApps()),
                ),
                const SizedBox(height: RA_ShapeStyles.space8),
                _SettingsAction(
                  icon: Icons.phone_android_rounded,
                  title: 'Manufacturer Battery Guide (Samsung / Xiaomi / Oppo)',
                  subtitle:
                      'Tailored steps to stop OEM battery savers silencing alarms.',
                  onTap: () => unawaited(_openOemBatteryGuide()),
                ),
              ],
            ),
          ),
          RA_FormSection(
            label: 'Import/Export',
            child: Column(
              children: [
                _SettingsAction(
                  icon: Icons.file_upload,
                  title: 'Export Routines',
                  subtitle: 'Copy a shareable RA1 string of all routines.',
                  trailing: !isPro ? const RA_ProBadge() : null,
                  onTap: () => unawaited(_export(context, ref)),
                ),
                const SizedBox(height: RA_ShapeStyles.space8),
                _SettingsAction(
                  icon: Icons.file_download,
                  title: 'Import Routines',
                  subtitle: 'Paste an RA1 code or preset link to add routines.',
                  onTap: () => unawaited(_import(context, ref)),
                ),
              ],
            ),
          ),
          RA_FormSection(
            label: 'About & Legal',
            bottomSpacing: RA_ShapeStyles.space48,
            child: Column(
              children: [
                _SettingsAction(
                  icon: Icons.star_outline_rounded,
                  title: 'Rate Rolling Alarm',
                  subtitle:
                      'Enjoying Rolling Alarm? Leave a quick rating on Google Play.',
                  onTap: () => unawaited(RA_ReviewService.openStoreListing()),
                ),
                const SizedBox(height: RA_ShapeStyles.space8),
                _SettingsAction(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  subtitle: 'Zero data collection · 100% offline privacy.',
                  onTap: () =>
                      unawaited(_openLegalUrl(RA_PurchaseService.privacyPolicyUrl)),
                ),
                const SizedBox(height: RA_ShapeStyles.space8),
                _SettingsAction(
                  icon: Icons.description_outlined,
                  title: 'Terms of Use',
                  subtitle: 'Licensing, billing, and subscription terms.',
                  onTap: () =>
                      unawaited(_openLegalUrl(RA_PurchaseService.termsOfUseUrl)),
                ),
                const SizedBox(height: RA_ShapeStyles.space8),
                DecoratedBox(
                  decoration: RA_ShapeStyles.elevatedSurface(),
                  child: Padding(
                    padding: const EdgeInsets.all(RA_ShapeStyles.space16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: RA_ColourStyles.secondary,
                        ),
                        const SizedBox(width: RA_ShapeStyles.space16),
                        Expanded(
                          child: Text(
                            'Rolling Alarm',
                            style: RA_TextStyles.smallFont,
                          ),
                        ),
                        Text(
                          'Version $_appVersion',
                          style: RA_TextStyles.tinyFont.copyWith(
                            color: RA_ColourStyles.mutedPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickSideButtonAction(
    BuildContext context,
    WidgetRef ref,
    AlarmSideButtonEnum button,
    AlarmSideButtonsSettings settings,
  ) async {
    if (!ref.read(IsProProvider)) {
      final unlocked = await PaywallPage.show(
        context,
        featureTrigger: 'Control alarms with hardware Volume buttons in Pro',
      );
      if (!unlocked || !context.mounted) return;
    }

    final selected = await showDialog<AlarmSideButtonActionEnum>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RA_ColourStyles.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: RA_ShapeStyles.largeBorderRadius,
        ),
        title: Text(button.label, style: RA_TextStyles.mediumFont),
        content: SingleChildScrollView(
          child: RA_RadioGroup<AlarmSideButtonActionEnum>(
            groupValue: settings.actionFor(button),
            onChanged: (v) => Navigator.pop(ctx, v),
            options: const [
              RA_RadioOption(
                value: AlarmSideButtonActionEnum.None,
                title: 'None',
              ),
              RA_RadioOption(
                value: AlarmSideButtonActionEnum.Snooze,
                title: 'Snooze',
              ),
              RA_RadioOption(
                value: AlarmSideButtonActionEnum.Dismiss,
                title: 'Dismiss',
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    await ref
        .read(AlarmSideButtonsProvider.notifier)
        .setButtonAction(button: button, action: selected);
  }

  Future<void> _pickSwipeAction(
    BuildContext context,
    WidgetRef ref,
    RoutineSwipeDirectionEnum direction,
    RoutineSwipeActionsSettings settings, {
    required bool isPro,
  }) async {
    final selected = await showDialog<RoutineSwipeActionEnum>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RA_ColourStyles.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: RA_ShapeStyles.largeBorderRadius,
        ),
        title: Text(direction.label, style: RA_TextStyles.mediumFont),
        content: SingleChildScrollView(
          child: RA_RadioGroup<RoutineSwipeActionEnum>(
            groupValue: settings.actionFor(direction),
            onChanged: (v) => Navigator.pop(ctx, v),
            options: [
              const RA_RadioOption(
                value: RoutineSwipeActionEnum.Mute,
                title: 'Mute',
              ),
              const RA_RadioOption(
                value: RoutineSwipeActionEnum.Pause,
                title: 'Pause/Resume',
              ),
              const RA_RadioOption(
                value: RoutineSwipeActionEnum.ResetInterval,
                title: 'Dismiss Early',
              ),
              RA_RadioOption(
                value: RoutineSwipeActionEnum.AddForToday,
                title: 'Adjust Today\'s Max',
                trailing: !isPro ? const RA_ProBadge() : null,
              ),
              const RA_RadioOption(
                value: RoutineSwipeActionEnum.Delete,
                title: 'Delete',
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    await ref
        .read(RoutineSwipeActionsProvider.notifier)
        .setDirectionAction(direction: direction, action: selected);
  }

  Future<void> _pickCardButtonAction(
    BuildContext context,
    WidgetRef ref,
    RoutineCardButtonPositionEnum position,
    RoutineCardButtonsSettings settings, {
    required bool isPro,
  }) async {
    final selected = await showDialog<RoutineSwipeActionEnum>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RA_ColourStyles.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: RA_ShapeStyles.largeBorderRadius,
        ),
        title: Text(position.label, style: RA_TextStyles.mediumFont),
        content: SingleChildScrollView(
          child: RA_RadioGroup<RoutineSwipeActionEnum>(
            groupValue: settings.actionFor(position),
            onChanged: (v) => Navigator.pop(ctx, v),
            options: [
              const RA_RadioOption(
                value: RoutineSwipeActionEnum.Mute,
                title: 'Mute',
              ),
              const RA_RadioOption(
                value: RoutineSwipeActionEnum.Pause,
                title: 'Pause/Resume',
              ),
              const RA_RadioOption(
                value: RoutineSwipeActionEnum.ResetInterval,
                title: 'Dismiss Early',
              ),
              RA_RadioOption(
                value: RoutineSwipeActionEnum.AddForToday,
                title: 'Adjust Today\'s Max',
                trailing: !isPro ? const RA_ProBadge() : null,
              ),
              const RA_RadioOption(
                value: RoutineSwipeActionEnum.Delete,
                title: 'Delete',
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    await ref
        .read(RoutineCardButtonsProvider.notifier)
        .setPositionAction(position: position, action: selected);
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    if (!ref.read(IsProProvider)) {
      final unlocked = await PaywallPage.show(
        context,
        featureTrigger: 'Export & back up routines with Pro',
      );
      if (!unlocked || !context.mounted) return;
    }

    final db = ref.read(RA_DatabaseProvider);
    final routines = await db.watchAllRoutines().first;
    if (!context.mounted) return;
    if (routines.isEmpty) {
      RA_showNoRoutinesToExportWarning(context);
      return;
    }

    final exportStr = await RA_tryAsync(
      () => RA_ExportService.exportToBase64(db),
    );
    if (exportStr != null && context.mounted) {
      unawaited(RA_showExportDialog(context, exportStr));
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    var importedCount = 0;
    await RA_showImportDialog(
      context,
      onImport: (text) async {
        final payload = RA_ExportService.decodeExportString(text);
        final rawRoutines = payload['routines'] as List<Object?>;
        final incomingCount = rawRoutines.length;
        final db = ref.read(RA_DatabaseProvider);

        if (!ref.read(IsProProvider) && incomingCount > 0) {
          final existingLiveCount = await db.countLiveRoutines();
          if (existingLiveCount + incomingCount >
              RA_PurchaseService.freeRoutineLimit) {
            if (!context.mounted) return false;
            final unlocked = await PaywallPage.show(
              context,
              featureTrigger: 'Import unlimited routines & backups with Pro',
            );
            if (!unlocked || !context.mounted) return false;
          }
        }

        final importedIds = await RA_ExportService.importFromBase64(db, text);
        importedCount = importedIds.length;
        await _scheduleImported(db, importedIds);
        return true;
      },
    );
    if (importedCount > 0 && context.mounted) {
      await RA_PermissionService.ensureCoreAlarmPermissions(context);
      await _refreshReliabilityStatus();
    }
  }

  /// Arms the exact alarm for each freshly imported routine, so an imported
  /// routine rings without needing to be opened and saved again.
  Future<void> _scheduleImported(RA_Database db, List<int> routineIds) async {
    for (final routineId in routineIds) {
      final routine = await db.getRoutineById(routineId);
      if (!routine.IsActive) continue;
      final state = await db.getRoutineState(routineId);
      final next = state?.NextTriggerTime;
      if (next == null) continue;
      await RA_AlarmService.scheduleNext(
        routineId: routineId,
        triggerTime: next,
        dbPath: widget.dbPath,
        routineName: routine.Name,
        routine: routine,
        state: state,
        refreshWidget: false,
      );
    }
    await RA_WidgetService.updateWidgetState(db: db);
  }
}

/// Equal height tiles for Volume Up / Volume Down side button actions.
class _SideButtonsTileRow extends StatelessWidget {
  final AlarmSideButtonsSettings settings;
  final ValueChanged<AlarmSideButtonEnum> onSelect;

  const _SideButtonsTileRow({required this.settings, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < AlarmSideButtonEnum.values.length; i++) ...[
            if (i > 0) const SizedBox(width: RA_ShapeStyles.space8),
            Expanded(
              child: _SideButtonTile(
                button: AlarmSideButtonEnum.values[i],
                action: settings.actionFor(AlarmSideButtonEnum.values[i]),
                onTap: () => onSelect(AlarmSideButtonEnum.values[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact tappable cell: muted button label over the chosen action.
class _SideButtonTile extends StatelessWidget {
  final AlarmSideButtonEnum button;
  final AlarmSideButtonActionEnum action;
  final VoidCallback onTap;

  const _SideButtonTile({
    required this.button,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return RA_PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            RA_Haptics.heavyUnawaited();
            onTap();
          },
          borderRadius: RA_ShapeStyles.largeBorderRadius,
          splashColor: RA_ColourStyles.secondary.withValues(alpha: 0.16),
          highlightColor: RA_ColourStyles.secondary.withValues(alpha: 0.08),
          child: DecoratedBox(
            decoration: RA_ShapeStyles.elevatedSurface(),
            child: Padding(
              padding: const EdgeInsets.all(RA_ShapeStyles.space8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RA_FittedText(
                    button.label,
                    alignment: Alignment.center,
                    style: RA_TextStyles.tinyFont.copyWith(
                      color: RA_ColourStyles.mutedPrimary,
                    ),
                  ),
                  const SizedBox(height: RA_ShapeStyles.space8),
                  RA_FittedText(
                    action.label,
                    alignment: Alignment.center,
                    style: RA_TextStyles.smallFont.copyWith(
                      color: RA_ColourStyles.valueText,
                    ),
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

/// Equal height tiles for Left / Right swipe actions.
class _SwipeActionsTileRow extends StatelessWidget {
  final RoutineSwipeActionsSettings settings;
  final ValueChanged<RoutineSwipeDirectionEnum> onSelect;

  const _SwipeActionsTileRow({required this.settings, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < RoutineSwipeDirectionEnum.values.length; i++) ...[
            if (i > 0) const SizedBox(width: RA_ShapeStyles.space8),
            Expanded(
              child: _SwipeActionTile(
                direction: RoutineSwipeDirectionEnum.values[i],
                action: settings.actionFor(RoutineSwipeDirectionEnum.values[i]),
                onTap: () => onSelect(RoutineSwipeDirectionEnum.values[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact tappable cell: muted direction label over the chosen swipe action.
class _SwipeActionTile extends StatelessWidget {
  final RoutineSwipeDirectionEnum direction;
  final RoutineSwipeActionEnum action;
  final VoidCallback onTap;

  const _SwipeActionTile({
    required this.direction,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return RA_PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            RA_Haptics.heavyUnawaited();
            onTap();
          },
          borderRadius: RA_ShapeStyles.largeBorderRadius,
          splashColor: RA_ColourStyles.secondary.withValues(alpha: 0.16),
          highlightColor: RA_ColourStyles.secondary.withValues(alpha: 0.08),
          child: DecoratedBox(
            decoration: RA_ShapeStyles.elevatedSurface(),
            child: Padding(
              padding: const EdgeInsets.all(RA_ShapeStyles.space8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RA_FittedText(
                    direction.label,
                    alignment: Alignment.center,
                    style: RA_TextStyles.tinyFont.copyWith(
                      color: RA_ColourStyles.mutedPrimary,
                    ),
                  ),
                  const SizedBox(height: RA_ShapeStyles.space8),
                  RA_FittedText(
                    action.label,
                    alignment: Alignment.center,
                    style: RA_TextStyles.smallFont.copyWith(
                      color: RA_ColourStyles.readableAccent(action.color()),
                    ),
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

/// Tappable reliability row with icon, title, live status badge, and subtitle.
class _ReliabilityActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isActive;
  final VoidCallback onTap;

  const _ReliabilityActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final badgeColor = isActive
        ? RA_ColourStyles.secondary
        : RA_ColourStyles.pauseOchre;
    return RA_PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            RA_Haptics.heavyUnawaited();
            onTap();
          },
          borderRadius: RA_ShapeStyles.largeBorderRadius,
          splashColor: badgeColor.withValues(alpha: 0.16),
          highlightColor: badgeColor.withValues(alpha: 0.08),
          child: DecoratedBox(
            decoration: RA_ShapeStyles.elevatedSurface(),
            child: Padding(
              padding: const EdgeInsets.all(RA_ShapeStyles.space16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(icon, color: badgeColor),
                  ),
                  const SizedBox(width: RA_ShapeStyles.space16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: RA_TextStyles.smallFont,
                              ),
                            ),
                            const SizedBox(width: RA_ShapeStyles.space8),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: badgeColor.withValues(alpha: 0.15),
                                borderRadius: RA_ShapeStyles.tinyBorderRadius,
                                border: Border.all(
                                  color: badgeColor.withValues(alpha: 0.45),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: RA_ShapeStyles.space8,
                                  vertical: 2,
                                ),
                                child: Text(
                                  isActive ? 'Active' : 'Recommended',
                                  style: RA_TextStyles.tinyFont.copyWith(
                                    color: RA_ColourStyles.readableAccent(
                                      badgeColor,
                                    ),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: RA_ShapeStyles.space8),
                        Text(
                          subtitle,
                          style: RA_TextStyles.tinyFont.copyWith(
                            color: RA_ColourStyles.mutedPrimary,
                          ),
                        ),
                      ],
                    ),
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

/// Tappable settings row with icon, title, optional trailing badge, and subtitle.
class _SettingsAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _SettingsAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return RA_PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            RA_Haptics.heavyUnawaited();
            onTap();
          },
          borderRadius: RA_ShapeStyles.largeBorderRadius,
          splashColor: RA_ColourStyles.secondary.withValues(alpha: 0.16),
          highlightColor: RA_ColourStyles.secondary.withValues(alpha: 0.08),
          child: DecoratedBox(
            decoration: RA_ShapeStyles.elevatedSurface(),
            child: Padding(
              padding: const EdgeInsets.all(RA_ShapeStyles.space16),
              child: Row(
                children: [
                  Icon(icon, color: RA_ColourStyles.secondary),
                  const SizedBox(width: RA_ShapeStyles.space16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(title, style: RA_TextStyles.smallFont),
                            ),
                            if (trailing != null) ...[
                              const SizedBox(width: RA_ShapeStyles.space8),
                              trailing!,
                            ],
                          ],
                        ),
                        const SizedBox(height: RA_ShapeStyles.space8),
                        Text(
                          subtitle,
                          style: RA_TextStyles.tinyFont.copyWith(
                            color: RA_ColourStyles.mutedPrimary,
                          ),
                        ),
                      ],
                    ),
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

class _ProUnlockedSection extends StatelessWidget {
  final bool isLegacyEarlySupporter;
  final bool restoring;
  final VoidCallback onManageSubscription;
  final VoidCallback onRestorePurchases;

  const _ProUnlockedSection({
    required this.isLegacyEarlySupporter,
    required this.restoring,
    required this.onManageSubscription,
    required this.onRestorePurchases,
  });

  @override
  Widget build(BuildContext context) {
    final badgeLabel = isLegacyEarlySupporter
        ? 'Legacy Early Supporter'
        : 'Active';
    final message = isLegacyEarlySupporter
        ? 'Thank you for supporting Rolling Alarm from the start. All Pro features are unlocked on this device.'
        : 'All Rolling Alarm Pro features are unlocked on this device.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: RA_ShapeStyles.elevatedSurface(
            borderColor: RA_ColourStyles.secondary.withValues(alpha: 0.5),
            borderWidth: 1.5,
            boxShadow: RA_ShapeStyles.tealGlow,
          ),
          child: Padding(
            padding: const EdgeInsets.all(RA_ShapeStyles.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: RA_ShapeStyles.space8,
                  runSpacing: RA_ShapeStyles.space8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.verified_rounded,
                          color: RA_ColourStyles.secondary,
                        ),
                        const SizedBox(width: 12),
                        Text('Pro Unlocked', style: RA_TextStyles.mediumFont),
                      ],
                    ),
                    RA_ProBadge(label: badgeLabel),
                  ],
                ),
                const SizedBox(height: RA_ShapeStyles.space8),
                Text(
                  message,
                  style: RA_TextStyles.tinyFont.copyWith(
                    color: RA_ColourStyles.mutedPrimary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: RA_ShapeStyles.space8),
        _SettingsAction(
          icon: Icons.manage_accounts_outlined,
          title: 'Manage Subscription',
          subtitle: 'View or cancel your plan in Google Play Subscriptions.',
          onTap: onManageSubscription,
        ),
        const SizedBox(height: RA_ShapeStyles.space8),
        _SettingsAction(
          icon: Icons.restore_rounded,
          title: restoring ? 'Restoring Purchases…' : 'Restore Purchases',
          subtitle: 'Sync your Google Play purchases on this device.',
          onTap: onRestorePurchases,
        ),
      ],
    );
  }
}

class _ProUpgradeSection extends StatelessWidget {
  final bool restoring;
  final VoidCallback onUpgrade;
  final VoidCallback onRestorePurchases;

  const _ProUpgradeSection({
    required this.restoring,
    required this.onUpgrade,
    required this.onRestorePurchases,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RA_PressScale(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                RA_Haptics.heavyUnawaited();
                onUpgrade();
              },
              borderRadius: RA_ShapeStyles.largeBorderRadius,
              splashColor: RA_ColourStyles.secondary.withValues(alpha: 0.16),
              highlightColor: RA_ColourStyles.secondary.withValues(alpha: 0.08),
              child: Ink(
                decoration: RA_ShapeStyles.elevatedSurface(
                  borderColor: RA_ColourStyles.secondary.withValues(alpha: 0.55),
                  borderWidth: 1.5,
                  boxShadow: RA_ShapeStyles.tealGlow,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(RA_ShapeStyles.space16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.workspace_premium_outlined,
                        color: RA_ColourStyles.secondary,
                        size: 28,
                      ),
                      const SizedBox(width: RA_ShapeStyles.space16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Upgrade to Rolling Alarm Pro',
                                    style: RA_TextStyles.smallFont.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: RA_ShapeStyles.space8),
                                const RA_ProBadge(),
                              ],
                            ),
                            const SizedBox(height: RA_ShapeStyles.space8),
                            Text(
                              'Unlimited routines, Classic Interval drift grid, custom audio, widgets & PDF reports.',
                              style: RA_TextStyles.tinyFont.copyWith(
                                color: RA_ColourStyles.mutedPrimary,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: RA_ShapeStyles.space8),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: RA_ColourStyles.secondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: RA_ShapeStyles.space8),
        _SettingsAction(
          icon: Icons.restore_rounded,
          title: restoring ? 'Restoring Purchases…' : 'Restore Purchases',
          subtitle: 'Already purchased Pro? Restore access from Google Play.',
          onTap: onRestorePurchases,
        ),
      ],
    );
  }
}

/// Equal height tiles for Left / Right card button actions.
class _CardButtonsTileRow extends StatelessWidget {
  final RoutineCardButtonsSettings settings;
  final ValueChanged<RoutineCardButtonPositionEnum> onSelect;

  const _CardButtonsTileRow({required this.settings, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < RoutineCardButtonPositionEnum.values.length; i++) ...[
            if (i > 0) const SizedBox(width: RA_ShapeStyles.space8),
            Expanded(
              child: _CardButtonTile(
                position: RoutineCardButtonPositionEnum.values[i],
                action: settings.actionFor(RoutineCardButtonPositionEnum.values[i]),
                onTap: () => onSelect(RoutineCardButtonPositionEnum.values[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CardButtonTile extends StatelessWidget {
  final RoutineCardButtonPositionEnum position;
  final RoutineSwipeActionEnum action;
  final VoidCallback onTap;

  const _CardButtonTile({
    required this.position,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return RA_PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            RA_Haptics.heavyUnawaited();
            onTap();
          },
          borderRadius: RA_ShapeStyles.largeBorderRadius,
          splashColor: RA_ColourStyles.secondary.withValues(alpha: 0.16),
          highlightColor: RA_ColourStyles.secondary.withValues(alpha: 0.08),
          child: DecoratedBox(
            decoration: RA_ShapeStyles.elevatedSurface(),
            child: Padding(
              padding: const EdgeInsets.all(RA_ShapeStyles.space8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RA_FittedText(
                    position.label,
                    alignment: Alignment.center,
                    style: RA_TextStyles.tinyFont.copyWith(
                      color: RA_ColourStyles.mutedPrimary,
                    ),
                  ),
                  const SizedBox(height: RA_ShapeStyles.space8),
                  RA_FittedText(
                    action.label,
                    alignment: Alignment.center,
                    style: RA_TextStyles.smallFont.copyWith(
                      color: RA_ColourStyles.readableAccent(action.color()),
                    ),
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
