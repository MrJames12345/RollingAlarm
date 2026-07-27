import 'package:flutter/material.dart';
import 'package:rolling_alarm/styles.dart';

/// Actions offered by the home routine card long-press menu.
enum RA_RoutineCardMenuAction {
  mute,
  pause,
  dismissUpcoming,
  edit,
  resetTodayCounter,
  delete,
}

/// Shows Mute, Pause, Dismiss Upcoming, Edit, Reset Today's Counter, and Delete.
///
/// Returns the chosen action, or `null` when dismissed without a choice.
Future<RA_RoutineCardMenuAction?> RA_showRoutineCardActionsDialog(
  BuildContext context, {
  required String routineName,
  required bool isMuted,
  required bool isPaused,
  required bool showDismissUpcoming,
}) {
  return showDialog<RA_RoutineCardMenuAction>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: RA_ColourStyles.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: RA_ShapeStyles.largeBorderRadius,
      ),
      title: Text(
        routineName,
        style: RA_TextStyles.mediumFont,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      contentPadding: const EdgeInsets.fromLTRB(
        RA_ShapeStyles.space8,
        RA_ShapeStyles.space8,
        RA_ShapeStyles.space8,
        RA_ShapeStyles.space16,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionTile(
            icon: isMuted
                ? Icons.notifications_off_rounded
                : Icons.notifications_off_outlined,
            label: isMuted ? 'Unmute' : 'Mute',
            color: isMuted ? RA_ColourStyles.sleepIndigo : null,
            onTap: () => Navigator.pop(ctx, RA_RoutineCardMenuAction.mute),
          ),
          _ActionTile(
            icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            label: isPaused ? 'Resume' : 'Pause',
            color: isPaused ? RA_ColourStyles.pauseOchre : null,
            onTap: () => Navigator.pop(ctx, RA_RoutineCardMenuAction.pause),
          ),
          if (showDismissUpcoming)
            _ActionTile(
              icon: Icons.skip_next,
              label: 'Dismiss Upcoming',
              onTap: () =>
                  Navigator.pop(ctx, RA_RoutineCardMenuAction.dismissUpcoming),
            ),
          _ActionTile(
            icon: Icons.edit_outlined,
            label: 'Edit',
            onTap: () => Navigator.pop(ctx, RA_RoutineCardMenuAction.edit),
          ),
          _ActionTile(
            icon: Icons.restart_alt_rounded,
            label: "Reset Today's Counter",
            onTap: () =>
                Navigator.pop(ctx, RA_RoutineCardMenuAction.resetTodayCounter),
          ),
          _ActionTile(
            icon: Icons.delete_outline,
            label: 'Delete',
            color: RA_ColourStyles.softCoral,
            onTap: () => Navigator.pop(ctx, RA_RoutineCardMenuAction.delete),
          ),
        ],
      ),
    ),
  );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? RA_ColourStyles.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: RA_ShapeStyles.tinyBorderRadius,
        splashColor: c.withValues(alpha: 0.2),
        highlightColor: c.withValues(alpha: 0.1),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: RA_ShapeStyles.minTouchTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RA_ShapeStyles.space16,
              vertical: RA_ShapeStyles.space8,
            ),
            child: Row(
              children: [
                Icon(icon, size: 22, color: c),
                const SizedBox(width: RA_ShapeStyles.space16),
                Expanded(
                  child: Text(
                    label,
                    style: RA_TextStyles.smallFont.copyWith(color: c),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
