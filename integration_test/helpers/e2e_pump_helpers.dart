import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bounded frame pumps for E2E.
///
/// Countdown StreamProviders and [AlarmRingPage] pulse animations never reach
/// idle, so [WidgetTester.pumpAndSettle] / Patrol `pumpAndSettle` hang or
/// time out. Prefer these helpers instead.
Future<void> pumpFrames(
  WidgetTester tester, {
  int frames = 15,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

/// Pumps until [finder] has at least one match, or [timeout] elapses.
Future<bool> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 12),
  Duration step = const Duration(milliseconds: 200),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) return true;
  }
  return finder.evaluate().isNotEmpty;
}

/// Pumps until [finder] has no matches, or [timeout] elapses.
Future<bool> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  Duration step = const Duration(milliseconds: 200),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    if (finder.evaluate().isEmpty) return true;
  }
  return finder.evaluate().isEmpty;
}

/// Pumps until [condition] returns true, or [timeout] elapses.
Future<bool> pumpUntilCondition(
  WidgetTester tester,
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 15),
  Duration step = const Duration(milliseconds: 200),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    if (await condition()) return true;
  }
  return condition();
}

/// Strict FlutterError forwarding for E2E suites.
///
/// Layout overflows (`RenderFlex`), Material/ListTile nesting errors, and
/// deactivated-ancestor assertions are intentionally NOT suppressed so any UI
/// regression fails integration tests loudly.
void installKnownUiErrorFilter() {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    previousOnError?.call(details);
  };
}

/// Completes an AlarmRingPage slide-to-confirm control.
///
/// Product UI uses "Slide to snooze" / "Slide to dismiss" tracks rather than
/// plain buttons. Drag far enough that progress crosses the 0.92 threshold.
Future<void> slideRingAction(
  WidgetTester tester,
  String label, {
  Key? trackKey,
  double dragDx = 520,
}) async {
  final labelFinder = find.text(label);
  final found = await pumpUntilFound(
    tester,
    labelFinder,
    timeout: const Duration(seconds: 8),
  );
  expect(found, isTrue, reason: 'Ring slide label "$label" must be visible');

  final target = trackKey != null ? find.byKey(trackKey) : labelFinder;

  // timedDrag keeps the pointer down while moving so the horizontal drag
  // recognizer accumulates progress across the track width.
  await tester.timedDrag(
    target,
    Offset(dragDx, 0),
    const Duration(milliseconds: 500),
  );
  await pumpFrames(tester, frames: 25);
}

/// Convenience wrappers for the ring slide controls.
Future<void> slideToSnooze(WidgetTester tester) => slideRingAction(
      tester,
      'Slide to snooze',
      trackKey: const Key('ra_ring_snooze'),
    );

Future<void> slideToDismiss(WidgetTester tester) => slideRingAction(
      tester,
      'Slide to dismiss',
      trackKey: const Key('ra_ring_dismiss'),
    );
