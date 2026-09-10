import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'primary_button_glow.dart';

/// Compact filled CTA used for inline primary actions inside cards.
class CompactPrimaryButton extends StatelessWidget {
  const CompactPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.isLoading = false,
    this.minimumWidth = 0,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool isLoading;
  final double minimumWidth;

  @override
  Widget build(BuildContext context) {
    final background = backgroundColor ?? AppColors.brandRed;
    final foreground = foregroundColor ?? AppColors.onBrandRed;
    return PrimaryButtonGlow(
      enabled:
          onPressed != null && !isLoading && background == AppColors.brandRed,
      radius: 8,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          disabledBackgroundColor: background.withValues(alpha: 0.45),
          foregroundColor: foreground,
          disabledForegroundColor: foreground,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.cardPadding,
            vertical: AppSpacing.chipGap,
          ),
          minimumSize: Size(minimumWidth, 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: isLoading
            ? Semantics(
                label: label,
                child: SizedBox.square(
                  dimension: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                ),
              )
            : Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: foreground,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}
