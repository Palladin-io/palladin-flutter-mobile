import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Neutral card surface for a semantic warning or destructive action.
class ActionZone extends StatelessWidget {
  const ActionZone({
    super.key,
    required this.title,
    required this.semanticColor,
    this.child,
    this.trailing,
    this.heading,
    this.borderColor,
    this.titleFontSize = 13,
    this.padding = const EdgeInsets.all(AppSpacing.cardPadding),
  });

  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final double titleFontSize;
  final String title;
  final String? heading;
  final Color semanticColor;
  final Widget? child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor ?? semanticColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: title,
                        style: TextStyle(color: semanticColor),
                      ),
                      if (heading != null) ...[
                        TextSpan(
                          text: ' | ',
                          style: TextStyle(
                            color: AppColors.onSurfaceSubtle(brightness),
                          ),
                        ),
                        TextSpan(
                          text: heading,
                          style: TextStyle(
                            color: AppColors.onSurface(brightness),
                          ),
                        ),
                      ],
                    ],
                  ),
                  style: TextStyle(
                    fontSize: titleFontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.sm),
                trailing!,
              ],
            ],
          ),
          if (child != null) ...[
            const SizedBox(height: AppSpacing.fieldGap),
            child!,
          ],
        ],
      ),
    );
  }
}

/// Compact destructive action; the owner retains confirmation and permissions.
class CompactDangerZone extends StatelessWidget {
  const CompactDangerZone({
    super.key,
    required this.title,
    required this.heading,
    required this.onPressed,
    this.icon = Icons.delete_outline,
    this.actionIcon,
  });
  final String title;
  final String heading;
  final VoidCallback? onPressed;
  final IconData icon;
  final Widget? actionIcon;

  @override
  Widget build(BuildContext context) => ActionZone(
    title: title,
    heading: heading,
    semanticColor: AppColors.brandRed,
    titleFontSize: 12,
    borderColor: AppColors.cardBorder(Theme.of(context).brightness),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.sm,
    ),
    trailing: Tooltip(
      message: heading,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: heading,
        child: InkResponse(
          onTap: onPressed,
          radius: 16,
          child: SizedBox.square(
            dimension: AppSpacing.controlHeight,
            child: Center(
              child:
                  actionIcon ?? Icon(icon, size: 22, color: AppColors.brandRed),
            ),
          ),
        ),
      ),
    ),
  );
}
