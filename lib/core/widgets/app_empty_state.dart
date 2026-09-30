import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'primary_button.dart';

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });
  final IconData icon;
  final String title, hint;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenH,
          vertical: AppSpacing.xxxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.onSurface(brightness)),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface(brightness),
              ),
            ),
            const SizedBox(height: AppSpacing.chipGap),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textTertiaryMobile,
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: 240,
                child: PrimaryButton(
                  label: actionLabel!,
                  onPressed: onAction,
                  leading: actionIcon == null
                      ? null
                      : Icon(actionIcon, size: 17),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
