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
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        border: Border(top: BorderSide(color: AppColors.navBorder(brightness))),
      ),
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenH,
            vertical: AppSpacing.md,
          ),
          child: child,
        ),
      ),
    );
  }
}
