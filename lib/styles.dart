import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ----------- //
// - Colours - //
// ----------- //

class RA_ColourStyles {
  static Color primary =
          const Color(0xFFD4D2CF), // soft warm white
      secondary =
          const Color(0xFF6B9A92), // muted sage teal
      sleepIndigo =
          const Color(0xFF4A4766), // quiet indigo
      softCoral =
          const Color(0xFFC17F74), // dusty coral (alerts / ringing)
      offBlack =
          const Color(0xFF0A0A0A), // near-black scaffold
      surface = const Color(0xFF161616); // calm charcoal surface token

  /// Secondary copy / timestamps; never a washed Material grey.
  static Color get mutedPrimary => primary.withValues(alpha: 0.5);

  /// Dimmer metadata on dense rows.
  static Color get faintPrimary => primary.withValues(alpha: 0.35);
}

// -------- //
// - Text - //
// -------- //

class RA_TextStyles {
  static const List<FontFeature> tabularFeatures = [
    FontFeature.tabularFigures(),
  ];

  static TextStyle
      // Tiny
      tinyFont = GoogleFonts.inter(
        color: RA_ColourStyles.primary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.25,
        fontFeatures: tabularFeatures,
      ),
      // Small
      smallFont = GoogleFonts.inter(
        color: RA_ColourStyles.primary,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.25,
        fontFeatures: tabularFeatures,
      ),
      // Medium
      mediumFont = GoogleFonts.inter(
        color: RA_ColourStyles.primary,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.2,
        fontFeatures: tabularFeatures,
      ),
      // Large
      largeFont = GoogleFonts.inter(
        color: RA_ColourStyles.primary,
        fontSize: 24,
        fontWeight: FontWeight.bold,
        height: 1.2,
        fontFeatures: tabularFeatures,
      ),
      // Giant
      giantFont = GoogleFonts.inter(
        color: RA_ColourStyles.primary,
        fontSize: 36,
        fontWeight: FontWeight.bold,
        height: 1.1,
        fontFeatures: tabularFeatures,
      ),
      // Countdown (tabular figures for non-jittering numbers)
      countdownFont = GoogleFonts.inter(
        color: RA_ColourStyles.secondary,
        fontSize: 48,
        fontWeight: FontWeight.w700,
        height: 1.0,
        fontFeatures: tabularFeatures,
      );

  /// Countdown size tuned for narrow phones without losing tabular figures.
  static TextStyle countdownFontFor(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final fontSize = width < 340
        ? 36.0
        : width < 380
        ? 42.0
        : 48.0;
    return countdownFont.copyWith(fontSize: fontSize);
  }

  /// Countdown colour: sage while calm, dusty coral under 60s, blend under 5m.
  static Color countdownColor(Duration remaining) {
    final seconds = remaining.inSeconds;
    if (seconds <= 60) return RA_ColourStyles.softCoral;
    if (seconds <= 300) {
      final t = 1.0 - (seconds / 300.0);
      return Color.lerp(RA_ColourStyles.secondary, RA_ColourStyles.softCoral, t)!;
    }
    return RA_ColourStyles.secondary;
  }

  /// Interval / log timestamp digits: tabular, secondary, small-screen friendly.
  static TextStyle get intervalDigitsFont => tinyFont.copyWith(
        color: RA_ColourStyles.secondary,
        fontFeatures: tabularFeatures,
      );

  static TextStyle get timestampFont => tinyFont.copyWith(
        color: RA_ColourStyles.mutedPrimary,
        fontFeatures: tabularFeatures,
      );
}

// ---------- //
// - Shapes - //
// ---------- //

class RA_ShapeStyles {
  /// Strict 8dp base unit for layout rhythm.
  static const double space8 = 8;
  static const double space16 = 16;
  static const double space24 = 24;
  static const double space32 = 32;
  static const double space48 = 48;

  /// Material accessibility minimum for interactive targets.
  static const double minTouchTarget = 48;

  static const EdgeInsets bodyPadding = EdgeInsets.fromLTRB(
    space16,
    space16,
    space16,
    space8,
  );

  /// Home list clearance so the last routine card clears the FAB + glow.
  static const EdgeInsets bodyPaddingWithFab = EdgeInsets.fromLTRB(
    space16,
    space16,
    space16,
    space48 + space48,
  );

  static const Duration pageFadeDuration = Duration(milliseconds: 280);
  static const Duration stateTransitionDuration = Duration(milliseconds: 320);
  static const Duration pressFeedbackDuration = Duration(milliseconds: 90);
  static const Duration colorBlendDuration = Duration(milliseconds: 420);
  static const Duration slideSnapDuration = Duration(milliseconds: 220);

  static const BorderRadius microBorderRadius = BorderRadius.all(
    Radius.circular(4),
  );
  static const BorderRadius tinyBorderRadius = BorderRadius.all(
    Radius.circular(8),
  );
  static const BorderRadius largeBorderRadius = BorderRadius.all(
    Radius.circular(16),
  );

  /// Idle elevated surfaces: quiet sage hairline, no muddy grey fill.
  static Color idleSurfaceBorder = RA_ColourStyles.secondary.withValues(
    alpha: 0.1,
  );

  /// Elevated charcoal panel with optional active border / glow.
  static BoxDecoration elevatedSurface({
    Color? fill,
    Color? borderColor,
    double borderWidth = 1,
    List<BoxShadow>? boxShadow,
    BorderRadius borderRadius = largeBorderRadius,
  }) =>
      BoxDecoration(
        color: fill ?? RA_ColourStyles.surface,
        borderRadius: borderRadius,
        border: Border.all(
          color: borderColor ?? idleSurfaceBorder,
          width: borderWidth,
        ),
        boxShadow: boxShadow,
      );

  /// Soft sage bloom for active / counting-down surfaces.
  static List<BoxShadow> tealGlow = [
    BoxShadow(
      color: RA_ColourStyles.secondary.withValues(alpha: 0.12),
      spreadRadius: 0,
      blurRadius: 8,
      offset: Offset.zero,
    ),
    BoxShadow(
      color: RA_ColourStyles.secondary.withValues(alpha: 0.05),
      spreadRadius: 2,
      blurRadius: 16,
      offset: Offset.zero,
    ),
  ];

  static List<BoxShadow> softCoralGlow = [
    BoxShadow(
      color: RA_ColourStyles.softCoral.withValues(alpha: 0.14),
      spreadRadius: 0,
      blurRadius: 8,
      offset: Offset.zero,
    ),
    BoxShadow(
      color: RA_ColourStyles.softCoral.withValues(alpha: 0.06),
      spreadRadius: 2,
      blurRadius: 16,
      offset: Offset.zero,
    ),
  ];
}
