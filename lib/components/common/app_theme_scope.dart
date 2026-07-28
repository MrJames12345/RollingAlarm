import 'package:flutter/material.dart';
import 'package:rolling_alarm/enums/app_theme_mode.dart';

/// Propagates the active [AppThemeModeEnum] so chrome can depend on theme
/// changes even when colours are read from static [RA_ColourStyles] getters.
class RA_AppThemeScope extends InheritedWidget {
  final AppThemeModeEnum mode;

  const RA_AppThemeScope({
    super.key,
    required this.mode,
    required super.child,
  });

  static AppThemeModeEnum of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<RA_AppThemeScope>();
    assert(scope != null, 'RA_AppThemeScope missing above this context');
    return scope!.mode;
  }

  @override
  bool updateShouldNotify(RA_AppThemeScope oldWidget) => mode != oldWidget.mode;
}

/// Marks the entire navigator subtree dirty when [mode] flips.
///
/// Pages read [RA_ColourStyles] statically and often do not call [Theme.of],
/// so a MaterialApp theme change alone leaves routes painted in the old
/// palette. Visiting and dirtying every element forces a full re-read.
class RA_ThemeRebuildGate extends StatefulWidget {
  final AppThemeModeEnum mode;
  final Widget child;

  const RA_ThemeRebuildGate({
    super.key,
    required this.mode,
    required this.child,
  });

  @override
  State<RA_ThemeRebuildGate> createState() => _RA_ThemeRebuildGateState();
}

class _RA_ThemeRebuildGateState extends State<RA_ThemeRebuildGate> {
  @override
  void didUpdateWidget(covariant RA_ThemeRebuildGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode == widget.mode) return;
    final root = context as Element;
    void visit(Element element) {
      // markNeedsBuild no-ops when the element is inactive or defunct.
      element.markNeedsBuild();
      element.visitChildren(visit);
    }

    root.visitChildren(visit);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
