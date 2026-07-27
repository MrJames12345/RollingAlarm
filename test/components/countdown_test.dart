import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_alarm/components/routine/routine_countdown.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/styles.dart';

void main() {
  group('RA_Countdown Widget Tests', () {
    testWidgets('renders tabular figures and correct text style', (
      tester,
    ) async {
      final targetTime = DateTime.now().add(
        const Duration(hours: 1, minutes: 30, seconds: 45),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            CountdownProvider(targetTime).overrideWith(
              (ref) => const Duration(hours: 1, minutes: 30, seconds: 45),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(body: RA_Countdown(nextTriggerTime: targetTime)),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final textFinder = find.text('01:30:45');
      expect(textFinder, findsOneWidget);

      // Scope under RA_Countdown: MaterialApp can introduce other
      // AnimatedDefaultTextStyle ancestors (e.g. theme transitions).
      final animatedFinder = find.descendant(
        of: find.byType(RA_Countdown),
        matching: find.byType(AnimatedDefaultTextStyle),
      );
      expect(animatedFinder, findsOneWidget);
      final animated = tester.widget<AnimatedDefaultTextStyle>(animatedFinder);
      expect(
        animated.style.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      expect(animated.style.color, equals(RA_ColourStyles.secondary));
      // Design token must keep tabular figures for the countdown path.
      expect(
        RA_TextStyles.countdownFont.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    testWidgets('renders muted style when frozenRemaining is set', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: RA_Countdown(
                frozenRemaining: Duration(hours: 2, minutes: 5, seconds: 9),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('02:05:09'), findsOneWidget);
      final animatedFinder = find.descendant(
        of: find.byType(RA_Countdown),
        matching: find.byType(AnimatedDefaultTextStyle),
      );
      final animated = tester.widget<AnimatedDefaultTextStyle>(animatedFinder);
      expect(animated.style.color, equals(RA_ColourStyles.mutedPrimary));
    });
  });
}
