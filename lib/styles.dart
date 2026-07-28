import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rolling_alarm/enums/app_theme_mode.dart';

// ----------- //
// - Colours - //
// ----------- //

/// Brand colour tokens. Scaffold / text / surface swap with [apply]; accents
/// stay brand-stable so sage, indigo, and coral read the same in both modes.
class RA_ColourStyles {
  static AppThemeModeEnum _mode = AppThemeModeEnum.Dark;

  static AppThemeModeEnum get mode => _mode;

  static Brightness get brightness =>
      _mode == AppThemeModeEnum.Light ? Brightness.light : Brightness.dark;

  /// Activates the palette for [mode]. Call before building [ThemeData].
  static void apply(AppThemeModeEnum mode) {
    _mode = mode;
  }

  // Brand accents (shared)
  static const Color secondary = Color(0xFF6B9A92); // muted sage teal
  static const Color sleepIndigo = Color(0xFF4A4766); // quiet indigo
  static const Color softCoral = Color(0xFFC17F74); // dusty coral (alerts)
  static const Color pauseOchre = Color(0xFFA68B5C); // dusty warm ochre (pause)
  /// Near-black ink on sage / coral / ochre fills (stable across themes).
  static const Color onAccent = Color(0xFF0A0A0A);

  // Dark palette
  static const Color _darkPrimary = Color(0xFFD4D2CF); // soft warm white
  static const Color _darkScaffold = Color(0xFF0A0A0A); // near-black scaffold
  static const Color _darkSurface = Color(0xFF161616); // calm charcoal

  // Light palette: warm paper echoing the soft-warm brand neutrals
  static const Color _lightPrimary = Color(0xFF2C2B2A); // warm charcoal text
  static const Color _lightScaffold = Color(0xFFF5F4F1); // warm paper
  static const Color _lightSurface = Color(0xFFFFFFFF); // elevated white

  /// Soft warm white ink on dark accent fills (e.g. mute indigo).
  static const Color onDarkAccent = _darkPrimary;

  /// Body text / icons.
  static Color get primary =>
      _mode == AppThemeModeEnum.Light ? _lightPrimary : _darkPrimary;

  /// Scaffold / page background. Named for history; value swaps with theme.
  static Color get offBlack =>
      _mode == AppThemeModeEnum.Light ? _lightScaffold : _darkScaffold;

  /// Elevated panels (cards, dialogs, inputs).
  static Color get surface =>
      _mode == AppThemeModeEnum.Light ? _lightSurface : _darkSurface;

  /// Home routine card fill: white on paper, near-black on OLED.
  static Color get cardFill =>
      _mode == AppThemeModeEnum.Light ? _lightSurface : _darkScaffold;

  /// Hairline dividers on elevated surfaces.
  static Color get divider => _mode == AppThemeModeEnum.Light
      ? _lightPrimary.withValues(alpha: 0.12)
      : _darkScaffold.withValues(alpha: 0.55);

  /// Field / summary value digits: sage on dark, black on light.
  static Color get valueText =>
      _mode == AppThemeModeEnum.Light ? onAccent : secondary;

  /// Secondary copy / timestamps; never a washed Material grey.
  static Color get mutedPrimary => _mode == AppThemeModeEnum.Light
      ? onAccent.withValues(alpha: 0.72)
      : primary.withValues(alpha: 0.5);

  /// Dimmer metadata on dense rows.
  static Color get faintPrimary => _mode == AppThemeModeEnum.Light
      ? onAccent.withValues(alpha: 0.48)
      : primary.withValues(alpha: 0.35);
}

// -------- //
// - Text - //
// -------- //

class RA_TextStyles {
  static const List<FontFeature> tabularFeatures = [
    FontFeature.tabularFigures(),
  ];

  static TextStyle get tinyFont => GoogleFonts.inter(
    color: RA_ColourStyles.primary,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.25,
    fontFeatures: tabularFeatures,
  );

  static TextStyle get smallFont => GoogleFonts.inter(
    color: RA_ColourStyles.primary,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.25,
    fontFeatures: tabularFeatures,
  );

  static TextStyle get mediumFont => GoogleFonts.inter(
    color: RA_ColourStyles.primary,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.2,
    fontFeatures: tabularFeatures,
  );

  static TextStyle get largeFont => GoogleFonts.inter(
    color: RA_ColourStyles.primary,
    fontSize: 24,
    fontWeight: FontWeight.bold,
    height: 1.2,
    fontFeatures: tabularFeatures,
  );

  static TextStyle get giantFont => GoogleFonts.inter(
    color: RA_ColourStyles.primary,
    fontSize: 36,
    fontWeight: FontWeight.bold,
    height: 1.1,
    fontFeatures: tabularFeatures,
  );

  static TextStyle get countdownFont => GoogleFonts.inter(
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
      return Color.lerp(
        RA_ColourStyles.secondary,
        RA_ColourStyles.softCoral,
        t,
      )!;
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
  ///
  /// OS bottom navigation inset is applied by [RA_PageScaffold]'s [SafeArea],
  /// so this only adds content gutter above the FAB.
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
  static Color get idleSurfaceBorder => RA_ColourStyles.secondary.withValues(
    alpha: RA_ColourStyles.mode == AppThemeModeEnum.Light ? 0.28 : 0.1,
  );

  /// Elevated charcoal panel with optional active border / glow.
  static BoxDecoration elevatedSurface({
    Color? fill,
    Color? borderColor,
    double borderWidth = 1,
    List<BoxShadow>? boxShadow,
    BorderRadius borderRadius = largeBorderRadius,
  }) => BoxDecoration(
    color: fill ?? RA_ColourStyles.surface,
    borderRadius: borderRadius,
    border: Border.all(
      color: borderColor ?? idleSurfaceBorder,
      width: borderWidth,
    ),
    boxShadow: boxShadow,
  );

  /// Soft sage bloom for active / counting-down surfaces.
  static List<BoxShadow> get tealGlow => [
    BoxShadow(
      color: RA_ColourStyles.secondary.withValues(
        alpha: RA_ColourStyles.mode == AppThemeModeEnum.Light ? 0.18 : 0.12,
      ),
      spreadRadius: 0,
      blurRadius: 8,
      offset: Offset.zero,
    ),
    BoxShadow(
      color: RA_ColourStyles.secondary.withValues(
        alpha: RA_ColourStyles.mode == AppThemeModeEnum.Light ? 0.08 : 0.05,
      ),
      spreadRadius: 2,
      blurRadius: 16,
      offset: Offset.zero,
    ),
  ];

  static List<BoxShadow> get softCoralGlow => [
    BoxShadow(
      color: RA_ColourStyles.softCoral.withValues(
        alpha: RA_ColourStyles.mode == AppThemeModeEnum.Light ? 0.2 : 0.14,
      ),
      spreadRadius: 0,
      blurRadius: 8,
      offset: Offset.zero,
    ),
    BoxShadow(
      color: RA_ColourStyles.softCoral.withValues(
        alpha: RA_ColourStyles.mode == AppThemeModeEnum.Light ? 0.09 : 0.06,
      ),
      spreadRadius: 2,
      blurRadius: 16,
      offset: Offset.zero,
    ),
  ];
}

// --------- //
// - Theme - //
// --------- //

/// Builds [ThemeData] and system chrome from the active [RA_ColourStyles].
class RA_AppTheme {
  static ThemeData themeData() {
    final isLight = RA_ColourStyles.mode == AppThemeModeEnum.Light;
    final scaffold = RA_ColourStyles.offBlack;
    final surface = RA_ColourStyles.surface;
    final primary = RA_ColourStyles.primary;

    return ThemeData(
      useMaterial3: true,
      brightness: RA_ColourStyles.brightness,
      scaffoldBackgroundColor: scaffold,
      canvasColor: scaffold,
      cardColor: surface,
      dividerColor: RA_ColourStyles.divider,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      colorScheme: isLight
          ? ColorScheme.light(
              primary: RA_ColourStyles.secondary,
              secondary: RA_ColourStyles.secondary,
              surface: scaffold,
              surfaceDim: scaffold,
              surfaceBright: surface,
              surfaceContainerLowest: scaffold,
              surfaceContainerLow: scaffold,
              surfaceContainer: surface,
              surfaceContainerHigh: surface,
              surfaceContainerHighest: surface,
              surfaceTint: RA_ColourStyles.secondary,
              error: RA_ColourStyles.softCoral,
              onPrimary: RA_ColourStyles.onAccent,
              onSecondary: RA_ColourStyles.onAccent,
              onSurface: primary,
              onSurfaceVariant: RA_ColourStyles.mutedPrimary,
              onError: RA_ColourStyles.onAccent,
              outline: RA_ColourStyles.secondary.withValues(alpha: 0.35),
              outlineVariant: RA_ColourStyles.secondary.withValues(alpha: 0.16),
            )
          : ColorScheme.dark(
              primary: RA_ColourStyles.secondary,
              secondary: RA_ColourStyles.secondary,
              // Absolute OLED black for scaffold-level surfaces; charcoal only
              // for intentional elevated tokens. Pin every M3 container so
              // Material never injects washed-out default greys.
              surface: scaffold,
              surfaceDim: scaffold,
              surfaceBright: surface,
              surfaceContainerLowest: scaffold,
              surfaceContainerLow: scaffold,
              surfaceContainer: surface,
              surfaceContainerHigh: surface,
              surfaceContainerHighest: surface,
              surfaceTint: RA_ColourStyles.secondary,
              error: RA_ColourStyles.softCoral,
              onPrimary: RA_ColourStyles.onAccent,
              onSecondary: RA_ColourStyles.onAccent,
              onSurface: primary,
              onSurfaceVariant: RA_ColourStyles.mutedPrimary,
              onError: RA_ColourStyles.onAccent,
              outline: RA_ColourStyles.secondary.withValues(alpha: 0.28),
              outlineVariant: RA_ColourStyles.secondary.withValues(alpha: 0.1),
            ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: primary,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: primary, size: 24),
        actionsIconTheme: IconThemeData(color: primary, size: 24),
        titleTextStyle: RA_TextStyles.largeFont,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(
            RA_ShapeStyles.minTouchTarget,
            RA_ShapeStyles.minTouchTarget,
          ),
          tapTargetSize: MaterialTapTargetSize.padded,
          foregroundColor: primary,
          overlayColor: RA_ColourStyles.secondary.withValues(alpha: 0.12),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: RA_ColourStyles.secondary,
        foregroundColor: RA_ColourStyles.onAccent,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        splashColor: isLight
            ? RA_ColourStyles.onAccent.withValues(alpha: 0.18)
            : primary.withValues(alpha: 0.22),
        shape: RoundedRectangleBorder(
          borderRadius: RA_ShapeStyles.largeBorderRadius,
          side: isLight
              ? BorderSide(
                  color: RA_ColourStyles.onAccent.withValues(alpha: 0.14),
                  width: 1,
                )
              : BorderSide.none,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shadowColor: RA_ColourStyles.secondary,
          minimumSize: const Size(
            RA_ShapeStyles.minTouchTarget,
            RA_ShapeStyles.minTouchTarget + RA_ShapeStyles.space8,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: RA_ShapeStyles.largeBorderRadius,
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: RA_ColourStyles.secondary.withValues(alpha: 0.08),
        iconColor: primary,
        textColor: primary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: RA_ShapeStyles.space16,
        ),
        minVerticalPadding: RA_ShapeStyles.space8,
        minTileHeight: RA_ShapeStyles.minTouchTarget,
        shape: const RoundedRectangleBorder(
          borderRadius: RA_ShapeStyles.largeBorderRadius,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: RA_ShapeStyles.largeBorderRadius,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return RA_ColourStyles.secondary;
          }
          return primary.withValues(alpha: isLight ? 0.65 : 0.55);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return RA_ColourStyles.secondary.withValues(alpha: 0.28);
          }
          return primary.withValues(alpha: isLight ? 0.2 : 0.12);
        }),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return RA_ColourStyles.secondary;
          }
          return primary.withValues(alpha: isLight ? 0.55 : 0.45);
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: RA_ColourStyles.secondary,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: RA_ColourStyles.secondary,
        selectionColor: RA_ColourStyles.secondary.withValues(alpha: 0.2),
        selectionHandleColor: RA_ColourStyles.secondary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: RA_TextStyles.smallFont,
        actionTextColor: RA_ColourStyles.secondary,
        shape: RoundedRectangleBorder(
          borderRadius: RA_ShapeStyles.largeBorderRadius,
          side: BorderSide(color: RA_ShapeStyles.idleSurfaceBorder),
        ),
      ),
    );
  }

  static SystemUiOverlayStyle systemUiOverlayStyle() {
    final isLight = RA_ColourStyles.mode == AppThemeModeEnum.Light;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
      statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: RA_ColourStyles.offBlack,
      systemNavigationBarIconBrightness: isLight
          ? Brightness.dark
          : Brightness.light,
    );
  }
}
