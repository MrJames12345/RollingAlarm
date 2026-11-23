import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rolling_alarm/components/common/app_theme_scope.dart';
import 'package:rolling_alarm/components/common/haptics.dart';
import 'package:rolling_alarm/components/common/press_scale.dart';
import 'package:rolling_alarm/components/common/pro_badge.dart';
import 'package:rolling_alarm/components/common/section_label.dart';
import 'package:rolling_alarm/models/routine_template.dart';
import 'package:rolling_alarm/providers/providers.dart';
import 'package:rolling_alarm/styles.dart';

/// Compact horizontal strip of 1-tap Quick-Start Routine Templates.
class RA_QuickTemplatesStrip extends ConsumerWidget {
  final ValueChanged<RA_RoutineTemplate> onSelect;
  final String? selectedTemplateId;
  final EdgeInsetsGeometry horizontalPadding;

  const RA_QuickTemplatesStrip({
    super.key,
    required this.onSelect,
    this.selectedTemplateId,
    this.horizontalPadding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    RA_AppThemeScope.of(context);
    final isPro = ref.watch(IsProProvider);
    const templates = RA_RoutineTemplates.all;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: horizontalPadding,
          child: RA_SectionLabel('Quick Templates'),
        ),
        const SizedBox(height: RA_ShapeStyles.space8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: horizontalPadding,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < templates.length; index++) ...[
                  if (index > 0) const SizedBox(width: RA_ShapeStyles.space8),
                  _TemplateCard(
                    template: templates[index],
                    selected: templates[index].id == selectedTemplateId,
                    showProPill: templates[index].usesProDriftMode && !isPro,
                    onTap: () => onSelect(templates[index]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final RA_RoutineTemplate template;
  final bool selected;
  final bool showProPill;
  final VoidCallback onTap;

  const _TemplateCard({
    required this.template,
    required this.selected,
    required this.showProPill,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return RA_PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            RA_Haptics.heavyUnawaited();
            onTap();
          },
          borderRadius: RA_ShapeStyles.largeBorderRadius,
          splashColor: RA_ColourStyles.secondary.withValues(alpha: 0.16),
          highlightColor: RA_ColourStyles.secondary.withValues(alpha: 0.08),
          child: Ink(
            width: 248,
            decoration: RA_ShapeStyles.elevatedSurface(
              fill: selected
                  ? Color.alphaBlend(
                      RA_ColourStyles.secondary.withValues(alpha: 0.1),
                      RA_ColourStyles.surface,
                    )
                  : null,
              borderColor: selected
                  ? RA_ColourStyles.secondary.withValues(alpha: 0.55)
                  : null,
              borderWidth: selected ? 1.5 : 1,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RA_ShapeStyles.space16,
                vertical: 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Icon(
                        template.icon,
                        size: 18,
                        color: RA_ColourStyles.secondary,
                      ),
                      const SizedBox(width: RA_ShapeStyles.space8),
                      Expanded(
                        child: Text(
                          template.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: RA_TextStyles.tinyFont.copyWith(
                            color: selected
                                ? RA_ColourStyles.secondary
                                : RA_ColourStyles.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (showProPill) ...[
                        const SizedBox(width: 4),
                        const RA_ProBadge(),
                      ],
                    ],
                  ),
                  const SizedBox(height: RA_ShapeStyles.space8),
                  Text(
                    template.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RA_TextStyles.tinyFont.copyWith(
                      color: RA_ColourStyles.mutedPrimary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
