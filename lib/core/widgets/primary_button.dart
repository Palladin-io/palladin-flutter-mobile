import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'primary_button_glow.dart';

/// Shared full-width primary action with the brand glow.
///
/// Disabled labels are visually dimmed; loading state shows a circular
/// progress indicator in place of the label.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.leading,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    return PrimaryButtonGlow(
      enabled: enabled,
      child: SizedBox(
        width: double.infinity,
        height: AppSpacing.controlHeight,
        child: ElevatedButton(
          onPressed: enabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brandRed,
            disabledBackgroundColor: AppColors.brandRed,
            foregroundColor: AppColors.onBrandRed,
            disabledForegroundColor: AppColors.onBrandRed.withValues(
              alpha: 0.5,
            ),
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
                    color: AppColors.onBrandRed,
                  ),
                )
              : leading == null
              ? _label()
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Align(alignment: Alignment.centerLeft, child: leading),
                    Center(child: _label()),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _label() {
    return Text(
      label,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
  }
}
