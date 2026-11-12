import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class AccentButton extends StatelessWidget {
  const AccentButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = AppSpacing.controlHeight,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final double? height;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final foreground = AppColors.onSurface(Theme.of(context).brightness);
    return SizedBox(
      width: double.infinity,
      height: height,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: Size(0, compact ? 0 : AppSpacing.controlHeight),
          padding: compact
              ? const EdgeInsets.symmetric(
                  horizontal: AppSpacing.cardPadding,
                  vertical: AppSpacing.chipGap,
                )
              : null,
          tapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : null,
          foregroundColor: foreground,
          disabledForegroundColor: foreground.withValues(alpha: 0.4),
          side: BorderSide(color: foreground),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(compact ? 8 : 10),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: compact ? 10 : 13,
            fontWeight: compact ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
