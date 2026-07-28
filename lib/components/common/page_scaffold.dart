import 'package:flutter/material.dart';
import 'package:rolling_alarm/components/common/app_theme_scope.dart';
import 'package:rolling_alarm/styles.dart';

/// Standard app chrome: OLED scaffold and flat AppBar.
///
/// Text scale is clamped so countdown and dense rows stay readable on small
/// screens without blowing past the 8/16dp layout grid.
///
/// The body is wrapped in [SafeArea] with [SafeArea.top] false so content
/// clears the OS bottom navigation / gesture inset (and side cutouts) while
/// the [AppBar] continues to own the status bar region.
Widget RA_PageScaffold({
  required String title,
  required Widget body,
  List<Widget>? actions,
  Widget? leading,
  Widget? floatingActionButton,
}) {
  return Builder(
    builder: (context) {
      // Rebuild chrome when Settings flips light/dark; colours are static tokens.
      RA_AppThemeScope.of(context);
      return MediaQuery.withClampedTextScaling(
        minScaleFactor: 0.9,
        maxScaleFactor: 1.25,
        child: Scaffold(
          backgroundColor: RA_ColourStyles.offBlack,
          appBar: AppBar(
            title: Text(
              title,
              style: RA_TextStyles.largeFont,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            leading: leading,
            actions: actions,
          ),
          body: SafeArea(
            top: false,
            maintainBottomViewPadding: true,
            child: body,
          ),
          floatingActionButton: floatingActionButton,
        ),
      );
    },
  );
}
