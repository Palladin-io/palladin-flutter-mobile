import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Shared device-setup surface; feature owners supply status copy and actions.
class SetupCard extends StatelessWidget {
  const SetupCard({
    super.key,
    required this.title,
    required this.descriptions,
    required this.actions,
    this.borderColor,
  });

  final String title;
  final List<String> descriptions;
  final List<Widget> actions;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: BoxDecoration(
          color: AppColors.cardFill(brightness),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor ?? AppColors.cardBorder(brightness),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            for (final description in descriptions) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                description,
                style: TextStyle(
                  color: AppColors.onSurfaceMuted(brightness),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            ...actions,
          ],
        ),
      ),
    );
  }
}
