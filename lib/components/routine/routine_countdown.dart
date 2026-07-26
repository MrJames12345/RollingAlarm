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
class RA_Countdown extends ConsumerWidget {
  final DateTime nextTriggerTime;

  const RA_Countdown({super.key, required this.nextTriggerTime});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(CountdownProvider(nextTriggerTime));

    return async.when(
      data: (rem) {
        final color = RA_TextStyles.countdownColor(rem);
        final base = RA_TextStyles.countdownFontFor(context);
        return AnimatedDefaultTextStyle(
          duration: RA_ShapeStyles.colorBlendDuration,
          curve: Curves.easeInOut,
          style: base.copyWith(color: color),
          child: RA_FittedText(RA_Utils.formatCountdown(rem)),
        );
      },
      loading: () => RA_FittedText(
        '00:00:00',
        style: RA_TextStyles.countdownFontFor(context),
      ),
      error: (_, _) => RA_FittedText(
        '--:--:--',
        style: RA_TextStyles.countdownFontFor(context).copyWith(
          color: RA_ColourStyles.softCoral,
        ),
      ),
    );
  }
}
