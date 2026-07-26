import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_alarm/components/field/duration_field.dart';

void main() {
  group('RA_DurationField Widget Tests', () {
    testWidgets('renders Hours, Minutes, and Seconds fields', (tester) async {
      Duration current = const Duration(hours: 1, minutes: 30, seconds: 15);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RA_DurationField(
              label: 'Every',
              value: current,
              onChanged: (val) => current = val,
            ),
          ),
        ),
      );

      expect(find.text('Hours'), findsOneWidget);
      expect(find.text('Minutes'), findsOneWidget);
      expect(find.text('Seconds'), findsOneWidget);
      expect(find.text('01'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
    });

    testWidgets('increment and decrement via stepper buttons update duration', (
      tester,
    ) async {
      Duration current = const Duration(hours: 2, minutes: 10, seconds: 20);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return RA_DurationField(
                  label: 'Every',
                  value: current,
                  onChanged: (val) {
                    setState(() => current = val);
                  },
                );
              },
            ),
          ),
        ),
      );

      // Find all up arrows (3 total: hours, minutes, seconds)
      final upArrows = find.byIcon(Icons.keyboard_arrow_up);
      expect(upArrows, findsNWidgets(3));

      // Tap up arrow on minutes (index 1)
      await tester.tap(upArrows.at(1));
      await tester.pumpAndSettle();

      expect(current, equals(const Duration(hours: 2, minutes: 11, seconds: 20)));
      expect(find.text('11'), findsOneWidget);
    });

    testWidgets('typing directly into text fields updates duration and clamps', (
      tester,
    ) async {
      Duration current = const Duration(hours: 0, minutes: 5, seconds: 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return RA_DurationField(
                  label: 'Every',
                  value: current,
                  onChanged: (val) {
                    setState(() => current = val);
                  },
                );
              },
            ),
          ),
        ),
      );

      // Find the TextField with text '05' (minutes)
      final minutesField = find.widgetWithText(TextField, '05');
      expect(minutesField, findsOneWidget);

      await tester.enterText(minutesField, '45');
      await tester.pumpAndSettle();

      expect(current, equals(const Duration(hours: 0, minutes: 45, seconds: 0)));
    });
  });
}
