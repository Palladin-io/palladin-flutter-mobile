import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Reusable green-tinted "approve" CTA. Mirrors the web button style:
/// green text + icon on a translucent green fill with a green border.
///
/// Lives in `core/widgets/` so any feature (agents, vault, the shared
/// icon-color browser sheet) can render the same confirm affordance
/// without `core/` depending on a feature — and without duplicating the
/// styling.
class ApproveActionButton extends StatelessWidget {
  const ApproveActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.check_circle_outline,
    this.isLoading = false,
    this.height = 44,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool isLoading;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: TextButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: isLoading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppColors.positiveAccent,
                ),
              )
            : Icon(icon, size: 16, color: AppColors.positiveAccent),
        label: Text(
          label,
          style: const TextStyle(
            color: AppColors.positiveAccent,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.positiveAccent,
          disabledForegroundColor:
              AppColors.positiveAccent.withValues(alpha: 0.4),
          backgroundColor: AppColors.positiveAccent.withValues(alpha: 0.12),
          disabledBackgroundColor:
              AppColors.positiveAccent.withValues(alpha: 0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: AppColors.positiveAccent.withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
    );
  }
}
