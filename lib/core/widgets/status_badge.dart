import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// A compact status label; meaning is carried by text, never color alone.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  static const labelStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
  );

  static TextStyle resolvedLabelStyle(BuildContext context) => Theme.of(
    context,
  ).textTheme.bodyMedium!.merge(labelStyle).copyWith(inherit: false);

  static double naturalWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: resolvedLabelStyle(context)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width.ceilToDouble() + AppSpacing.innerGap * 2 + 3;
    painter.dispose();
    return width;
  }

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.innerGap,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: icon == null
          ? _label(context)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: color),
                const SizedBox(width: AppSpacing.xs),
                Flexible(child: _label(context)),
              ],
            ),
    );
  }

  Widget _label(BuildContext context) => Text(
    label,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: resolvedLabelStyle(context).copyWith(color: color),
  );
}
