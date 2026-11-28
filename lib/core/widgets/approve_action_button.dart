import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Neutral outlined approval action with a semantic green foreground.
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
    final brightness = Theme.of(context).brightness;
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
            : Icon(
                icon,
                size: 16,
                color: enabled ? AppColors.positiveAccent : null,
              ),
        label: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.positiveAccent,
          disabledForegroundColor: AppColors.positiveAccent.withValues(
            alpha: 0.4,
          ),
          backgroundColor: AppColors.cardFill(brightness),
          disabledBackgroundColor: AppColors.cardFill(brightness),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: AppColors.cardBorder(brightness)),
          ),
        ),
      ),
    );
  }
}
