import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/components/common/fade_switcher.dart';
import 'package:rolling_alarm/components/common/loading.dart';
import 'package:rolling_alarm/components/common/status_message.dart';

/// Shared fade switcher for Riverpod list pages (loading, error, empty, data).
Widget RA_AsyncListBody<T>({
  required AsyncValue<List<T>> async,
  required Widget Function(List<T> items) listBuilder,
  required Widget empty,
  required VoidCallback onRetry,
  required String errorTitle,
}) {
  return RA_FadeSwitcher(
    child: async.when(
      data: (items) => items.isEmpty
          ? RA_Keyed('empty', empty)
          : RA_Keyed('list', listBuilder(items)),
      loading: () => RA_Keyed('loading', const RA_Loading()),
      error: (_, _) => RA_Keyed(
        'error',
        RA_StatusMessage.error(title: errorTitle, onRetry: onRetry),
      ),
    ),
  );
}
