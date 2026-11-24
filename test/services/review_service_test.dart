import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_alarm/services/review.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RA_ReviewService.resetForTesting();
  });

  tearDown(() {
    RA_ReviewService.resetForTesting();
  });

  group('RA_ReviewService Milestone & Cooldown Tests', () {
    test(
      'requires >= 5 dismissals AND >= 3 distinct days before invoking requestReview',
      () async {
        var reviewCalls = 0;
        RA_ReviewService.debugIsAvailableOverride = () async => true;
        RA_ReviewService.debugRequestReviewOverride = () async {
          reviewCalls++;
        };

        final day1 = DateTime(2026, 6, 1, 8, 0);
        final day2 = DateTime(2026, 6, 2, 8, 0);
        final day3 = DateTime(2026, 6, 3, 8, 0);

        // 5 dismissals across only 2 distinct days -> must NOT prompt.
        expect(
          await RA_ReviewService.recordForegroundDismissalAndMaybePrompt(
            now: day1,
          ),
          isFalse,
        );
        expect(
          await RA_ReviewService.recordForegroundDismissalAndMaybePrompt(
            now: day1.add(const Duration(hours: 4)),
          ),
          isFalse,
        );
        expect(
          await RA_ReviewService.recordForegroundDismissalAndMaybePrompt(
            now: day1.add(const Duration(hours: 8)),
          ),
          isFalse,
        );
        expect(
          await RA_ReviewService.recordForegroundDismissalAndMaybePrompt(
            now: day2,
          ),
          isFalse,
        );
        expect(
          await RA_ReviewService.recordForegroundDismissalAndMaybePrompt(
            now: day2.add(const Duration(hours: 4)),
          ),
          isFalse,
        );
        expect(reviewCalls, equals(0));

        // 3rd distinct day (dismiss #6) -> satisfies >= 5 dismissals & >= 3 days!
        expect(
          await RA_ReviewService.recordForegroundDismissalAndMaybePrompt(
            now: day3,
          ),
          isTrue,
        );
        expect(reviewCalls, equals(1));

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt(RA_ReviewService.dismissCountKey), equals(6));
        expect(
          prefs.getString(RA_ReviewService.distinctDaysCsvKey),
          equals('2026-06-01,2026-06-02,2026-06-03'),
        );
        expect(
          prefs.getInt(RA_ReviewService.lastPromptEpochMsKey),
          equals(day3.millisecondsSinceEpoch),
        );
      },
    );

    test('enforces strict 120-day cooldown after prompting', () async {
      var reviewCalls = 0;
      RA_ReviewService.debugIsAvailableOverride = () async => true;
      RA_ReviewService.debugRequestReviewOverride = () async {
        reviewCalls++;
      };

      final firstPromptDay = DateTime(2026, 6, 3, 9, 0);
      SharedPreferences.setMockInitialValues({
        RA_ReviewService.dismissCountKey: 4,
        RA_ReviewService.distinctDaysCsvKey: '2026-06-01,2026-06-02',
      });

      // 5th dismiss on 3rd distinct day triggers prompt.
      expect(
        await RA_ReviewService.recordForegroundDismissalAndMaybePrompt(
          now: firstPromptDay,
        ),
        isTrue,
      );
      expect(reviewCalls, equals(1));

      // Day 119 -> still within cooldown, must NOT prompt.
      expect(
        await RA_ReviewService.recordForegroundDismissalAndMaybePrompt(
          now: firstPromptDay.add(const Duration(days: 119, hours: 23)),
        ),
        isFalse,
      );
      expect(reviewCalls, equals(1));

      // Exact Day 120 -> cooldown elapsed, may prompt again.
      expect(
        await RA_ReviewService.recordForegroundDismissalAndMaybePrompt(
          now: firstPromptDay.add(const Duration(days: 120)),
        ),
        isTrue,
      );
      expect(reviewCalls, equals(2));
    });

    test(
      'suppresses prompt when another alarm is ringing or Play API is unavailable without burning cooldown',
      () async {
        var reviewCalls = 0;
        var available = true;
        RA_ReviewService.debugIsAvailableOverride = () async => available;
        RA_ReviewService.debugRequestReviewOverride = () async {
          reviewCalls++;
        };

        SharedPreferences.setMockInitialValues({
          RA_ReviewService.dismissCountKey: 4,
          RA_ReviewService.distinctDaysCsvKey: '2026-06-01,2026-06-02',
        });

        final day3 = DateTime(2026, 6, 3, 8, 0);
        // Another alarm still ringing -> suppressed, cooldown untouched.
        expect(
          await RA_ReviewService.recordForegroundDismissalAndMaybePrompt(
            now: day3,
            hasOtherRingingAlarms: true,
          ),
          isFalse,
        );
        expect(reviewCalls, equals(0));

        // Play API unavailable -> suppressed, cooldown untouched.
        available = false;
        expect(
          await RA_ReviewService.recordForegroundDismissalAndMaybePrompt(
            now: day3.add(const Duration(hours: 2)),
          ),
          isFalse,
        );
        expect(reviewCalls, equals(0));
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt(RA_ReviewService.lastPromptEpochMsKey), isNull);

        // Once available and quiet -> prompts cleanly.
        available = true;
        expect(
          await RA_ReviewService.recordForegroundDismissalAndMaybePrompt(
            now: day3.add(const Duration(hours: 4)),
          ),
          isTrue,
        );
        expect(reviewCalls, equals(1));
      },
    );

    test('caps distinct days CSV to the most recent 10 days', () async {
      RA_ReviewService.debugIsAvailableOverride = () async => false;
      for (var d = 1; d <= 13; d++) {
        await RA_ReviewService.recordForegroundDismissalAndMaybePrompt(
          now: DateTime(2026, 6, d, 8, 0),
        );
      }
      final prefs = await SharedPreferences.getInstance();
      final days = prefs
          .getString(RA_ReviewService.distinctDaysCsvKey)!
          .split(',');
      expect(days, hasLength(10));
      expect(days.first, equals('2026-06-04'));
      expect(days.last, equals('2026-06-13'));
    });

    test('openStoreListing falls back to Google Play URL when native bridge throws', () async {
      String? launchedUrl;
      RA_ReviewService.debugOpenStoreListingOverride = () async {
        throw StateError('Play Store unavailable');
      };
      RA_ReviewService.debugOpenFallbackUrlOverride = (url) async {
        launchedUrl = url;
        return true;
      };

      final opened = await RA_ReviewService.openStoreListing();
      expect(opened, isTrue);
      expect(launchedUrl, equals(RA_ReviewService.playStoreListingUrl));
    });

    test(
      'failed requestReview does not burn 120-day cooldown and concurrent calls do not double-prompt',
      () async {
        SharedPreferences.setMockInitialValues({
          RA_ReviewService.dismissCountKey: 4,
          RA_ReviewService.distinctDaysCsvKey: '2026-06-01,2026-06-02',
        });

        final day3 = DateTime(2026, 6, 3, 9, 0);
        RA_ReviewService.debugIsAvailableOverride = () async => true;
        RA_ReviewService.debugRequestReviewOverride = () async {
          throw StateError('review_unavailable');
        };

        // Failure must return false AND leave lastPromptEpochMs unset.
        expect(
          await RA_ReviewService.recordForegroundDismissalAndMaybePrompt(
            now: day3,
          ),
          isFalse,
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt(RA_ReviewService.lastPromptEpochMsKey), isNull);

        // Concurrent calls while requestReview is in flight must invoke only once.
        final completer = Completer<void>();
        var requestCalls = 0;
        RA_ReviewService.debugRequestReviewOverride = () {
          requestCalls++;
          return completer.future;
        };

        final f1 = RA_ReviewService.recordForegroundDismissalAndMaybePrompt(
          now: day3.add(const Duration(minutes: 5)),
        );
        final f2 = RA_ReviewService.recordForegroundDismissalAndMaybePrompt(
          now: day3.add(const Duration(minutes: 5)),
        );
        await Future<void>.delayed(Duration.zero);
        completer.complete();

        final results = await Future.wait<bool>([f1, f2]);
        expect(requestCalls, equals(1));
        expect(results.where((r) => r).length, equals(1));
      },
    );
  });
}
