import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// A full-width OAuth sign-in button matching the Claw Vault design
/// prototype.
///
/// [icon] is displayed to the left of the [label]. When [enabled] is
/// `false` the button is visually dimmed and taps invoke [onDisabledTap]
/// instead of [onPressed].
class OAuthButton extends StatelessWidget {
  const OAuthButton({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.backgroundColor = Colors.white,
    this.foregroundColor = Colors.black87,
    this.enabled = true,
    this.onDisabledTap,
  });

  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool enabled;
  final VoidCallback? onDisabledTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : onDisabledTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: enabled
              ? backgroundColor
              : backgroundColor.withValues(alpha: 0.4),
          foregroundColor: enabled
              ? foregroundColor
              : foregroundColor.withValues(alpha: 0.4),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: enabled
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.05),
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 24, height: 24, child: icon),
            const SizedBox(width: AppSpacing.fieldGap),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: enabled
                    ? foregroundColor
                    : foregroundColor.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
