import 'dart:async';

import 'package:flutter/services.dart';

/// Central haptic entry points so primary actions stay consistent.
class RA_Haptics {
  RA_Haptics._();

  /// Fire-and-forget heavy impact for synchronous onPressed / onTap handlers.
  static void heavyUnawaited() => unawaited(HapticFeedback.heavyImpact());
}
