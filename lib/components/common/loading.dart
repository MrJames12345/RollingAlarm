import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rolling_alarm/styles.dart';

/// Centered teal progress indicator with a soft pulse for loading states.
class RA_Loading extends StatefulWidget {
  final double size;

  const RA_Loading({super.key, this.size = RA_ShapeStyles.space32});

  @override
  State<RA_Loading> createState() => _RA_LoadingState();
}

class _RA_LoadingState extends State<RA_Loading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    unawaited(_controller.repeat(reverse: true));
    _pulse = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final t = _pulse.value;
          return Opacity(
            opacity: 0.55 + (0.45 * t),
            child: Transform.scale(scale: 0.92 + (0.08 * t), child: child),
          );
        },
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: RA_ColourStyles.secondary,
          ),
        ),
      ),
    );
  }
}
