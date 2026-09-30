import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class AppActionFooter extends StatelessWidget {
  const AppActionFooter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(
        left: AppSpacing.screenH,
        top: AppSpacing.md,
        right: AppSpacing.screenH,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        border: Border(top: BorderSide(color: AppColors.navBorder(brightness))),
      ),
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        minimum: const EdgeInsets.only(bottom: AppSpacing.screenBottom),
        child: child,
      ),
    );
  }
}
