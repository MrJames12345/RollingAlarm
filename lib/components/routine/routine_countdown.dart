import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/components/common/fitted_text.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/styles.dart';
import 'package:rolling_alarm/utils.dart';

/// Displays a live countdown timer using tabular figures for
/// non-jittering numeric display.
///
/// This is the only widget that should watch [CountdownProvider]. Parent cards
/// watch phase snapshots so per-second ticks never rebuild full card chrome.
///
/// When [frozenRemaining] is set, the value is shown statically (paused) and
/// [CountdownProvider] is not watched.
class RA_Countdown extends ConsumerWidget {
  final DateTime? nextTriggerTime;
  final Duration? frozenRemaining;

  const RA_Countdown({super.key, this.nextTriggerTime, this.frozenRemaining})
    : assert(
        frozenRemaining != null || nextTriggerTime != null,
        'Provide nextTriggerTime or frozenRemaining',
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final frozen = frozenRemaining;
    if (frozen != null) {
      final base = RA_TextStyles.countdownFontFor(context);
      return AnimatedDefaultTextStyle(
        duration: RA_ShapeStyles.colorBlendDuration,
        curve: Curves.easeInOut,
        style: base.copyWith(color: RA_ColourStyles.mutedPrimary),
        child: RA_FittedText(RA_Utils.formatCountdown(frozen)),
      );
    }

    final rem = ref.watch(CountdownProvider(nextTriggerTime!));
    final color = RA_TextStyles.countdownColor(rem);
    final base = RA_TextStyles.countdownFontFor(context);
    return AnimatedDefaultTextStyle(
      duration: RA_ShapeStyles.colorBlendDuration,
      curve: Curves.easeInOut,
      style: base.copyWith(color: color),
      child: RA_FittedText(RA_Utils.formatCountdown(rem)),
    );
  }
}
