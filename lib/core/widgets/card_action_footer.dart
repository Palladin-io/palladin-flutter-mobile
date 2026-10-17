import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class CardActionFooter extends StatelessWidget {
  const CardActionFooter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      constraints: const BoxConstraints(minHeight: 46),
      decoration: BoxDecoration(
        color: AppColors.cardFooterOverlay(brightness),
        border: Border(
          top: BorderSide(color: AppColors.cardBorder(brightness)),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.cardPadding,
        vertical: AppSpacing.innerGap,
      ),
      child: Center(child: child),
    );
  }
}

class CardRevokeButton extends StatelessWidget {
  const CardRevokeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.height = 36,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final double? height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: height,
    child: OutlinedButton(
      onPressed: busy ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.brandRed,
        side: const BorderSide(color: AppColors.brandRed),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.brandRed,
              ),
            )
          : Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
    ),
  );
}
