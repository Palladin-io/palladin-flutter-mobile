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
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.cardBorder(brightness)),
        ),
      ),
      child: Center(child: child),
    );
  }
}

class CardFooterAction extends StatelessWidget {
  const CardFooterAction({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: AppSpacing.controlHeight,
    width: double.infinity,
    child: TextButton.icon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            )
          : Icon(icon, size: 14),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}

class CardRevokeButton extends StatelessWidget {
  const CardRevokeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => CardFooterAction(
    label: label,
    icon: Icons.block,
    color: AppColors.brandRed,
    onPressed: onPressed,
    loading: busy,
  );
}
