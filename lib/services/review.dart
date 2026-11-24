import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:rolling_alarm/services/purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Google Play-compliant milestone review prompt and Play Store listing helper.
///
/// Communicates with the native `com.google.android.play:review` bridge in
/// `PlayReviewBridge.kt` (`com.casellaweb.rolling_alarm/play_review`).
///
/// Tracks foreground alarm dismissals and distinct active calendar days locally
/// in [SharedPreferences]. Never displays any pre-screening sentiment dialog
/// ("Do you like Rolling Alarm?") and never invokes the review sheet from a
/// background isolate or while another alarm is actively ringing.
class RA_ReviewService {
  RA_ReviewService._();

  static const MethodChannel _reviewChannel = MethodChannel(
    'com.casellaweb.rolling_alarm/play_review',
  );

  static const String dismissCountKey = 'ra_review_dismiss_count';
  static const String distinctDaysCsvKey = 'ra_review_distinct_days_csv';
  static const String lastPromptEpochMsKey = 'ra_review_last_prompt_epoch_ms';

  static const int minDismissCount = 5;
  static const int minDistinctDays = 3;
  static const int maxStoredDays = 10;
  static const Duration promptCooldown = Duration(days: 120);

  static const String playStoreListingUrl =
      'https://play.google.com/store/apps/details?id=com.casellaweb.rolling_alarm';

  @visibleForTesting
  static Future<bool> Function()? debugIsAvailableOverride;

  @visibleForTesting
  static Future<void> Function()? debugRequestReviewOverride;

  @visibleForTesting
  static Future<void> Function()? debugOpenStoreListingOverride;

  @visibleForTesting
  static Future<bool> Function(String url)? debugOpenFallbackUrlOverride;

  static bool _promptInFlight = false;

  @visibleForTesting
  static void resetForTesting() {
    _promptInFlight = false;
    debugIsAvailableOverride = null;
    debugRequestReviewOverride = null;
    debugOpenStoreListingOverride = null;
    debugOpenFallbackUrlOverride = null;
  }

  static Future<bool> _nativeIsAvailable() async {
    try {
      final result = await _reviewChannel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _nativeRequestReview() async {
    await _reviewChannel.invokeMethod<void>('requestReview');
  }

  static Future<void> _nativeOpenStoreListing() async {
    await _reviewChannel.invokeMethod<void>('openStoreListing');
  }

  /// Records a manual foreground alarm dismissal from [AlarmRingPage] and
  /// requests Google Play's native in-app review sheet when all milestone and
  /// cooldown conditions are satisfied.
  ///
  /// Returns `true` when `requestReview()` was actually triggered.
  static Future<bool> recordForegroundDismissalAndMaybePrompt({
    DateTime? now,
    bool hasOtherRingingAlarms = false,
  }) async {
    try {
      final reference = (now ?? DateTime.now()).toLocal();
      final prefs = await SharedPreferences.getInstance();

      final dismissCount = (prefs.getInt(dismissCountKey) ?? 0) + 1;
      await prefs.setInt(dismissCountKey, dismissCount);

      final todayKey = _formatYmd(reference);
      final days = _parseDistinctDays(prefs.getString(distinctDaysCsvKey));
      if (!days.contains(todayKey)) {
        days.add(todayKey);
      }
      final trimmedDays = days.length > maxStoredDays
          ? days.sublist(days.length - maxStoredDays)
          : days;
      await prefs.setString(distinctDaysCsvKey, trimmedDays.join(','));

      if (hasOtherRingingAlarms || _promptInFlight) return false;
      if (dismissCount < minDismissCount) return false;
      if (trimmedDays.length < minDistinctDays) return false;

      final lastPromptMs = prefs.getInt(lastPromptEpochMsKey);
      if (lastPromptMs != null && lastPromptMs > 0) {
        final elapsedMs = reference.millisecondsSinceEpoch - lastPromptMs;
        if (elapsedMs < promptCooldown.inMilliseconds) {
          return false;
        }
      }

      _promptInFlight = true;
      try {
        final isAvailable =
            await (debugIsAvailableOverride ?? _nativeIsAvailable)();
        if (!isAvailable) return false;

        await (debugRequestReviewOverride ?? _nativeRequestReview)();
        await prefs.setInt(
          lastPromptEpochMsKey,
          reference.millisecondsSinceEpoch,
        );
        return true;
      } finally {
        _promptInFlight = false;
      }
    } catch (_) {
      return false;
    }
  }

  /// Opens the Rolling Alarm Play Store listing directly, falling back to
  /// `url_launcher` if the native Play Store bridge throws.
  static Future<bool> openStoreListing() async {
    try {
      await (debugOpenStoreListingOverride ?? _nativeOpenStoreListing)();
      return true;
    } catch (_) {
      try {
        return await (debugOpenFallbackUrlOverride ??
            RA_PurchaseService.openExternalUrl)(playStoreListingUrl);
      } catch (_) {
        return false;
      }
    }
  }

  static String _formatYmd(DateTime local) {
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static List<String> _parseDistinctDays(String? rawCsv) {
    if (rawCsv == null || rawCsv.trim().isEmpty) return <String>[];
    final seen = <String>{};
    final result = <String>[];
    for (final part in rawCsv.split(',')) {
      final token = part.trim();
      if (token.isNotEmpty && seen.add(token)) {
        result.add(token);
      }
    }
    return result;
  }
}
