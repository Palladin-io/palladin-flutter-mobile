import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// A full-width provider action using the app's standard glass outline style.
///
/// [icon] uses a fixed leading slot while [label] stays centered on the
/// button's axis, so labels align identically across providers.
class OAuthButton extends StatelessWidget {
  const OAuthButton({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.iconWidth = 24,
    this.iconHeight = 24,
  });

  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
  final double iconWidth;
  final double iconHeight;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final enabled = onPressed != null;
    return SizedBox(
      width: double.infinity,
      height: AppSpacing.controlHeight,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.cardFill(brightness),
          disabledBackgroundColor: AppColors.cardFill(brightness),
          foregroundColor: AppColors.onSurface(brightness),
          disabledForegroundColor: AppColors.onSurface(
            brightness,
          ).withValues(alpha: 0.4),
          side: BorderSide(color: AppColors.cardBorder(brightness)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        ),
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: iconWidth,
                  height: iconHeight,
                  child: icon,
                ),
              ),
              Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface(brightness),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
