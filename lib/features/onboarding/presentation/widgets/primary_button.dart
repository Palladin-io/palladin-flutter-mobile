import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Primary button used across onboarding screens.
///
/// Disabled state is visually dimmed; loading state shows a circular
/// progress indicator in place of the label.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandRed,
          disabledBackgroundColor: AppColors.brandRed.withValues(alpha: 0.3),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
