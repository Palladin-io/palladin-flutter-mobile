import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_colors.dart';
import 'app_brand_background.dart';

/// Auth alias for the shared application background.
class AuthBrandBackground extends StatelessWidget {
  const AuthBrandBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AppBrandBackground(
    lightPageGradient: AppColors.authEntryLightPageGradient,
    lightLogoGlow: AppColors.authEntryLightLogoGlow,
    child: child,
  );
}

/// Canonical side margins for auth and confirmation content.
///
/// Callers still add [AppSpacing.screenH] as a minimum gutter. On wider
/// phones this widget caps the content at 320 px and centers it, matching the
/// provider buttons on the authentication entry screen.
class AuthContentWidth extends StatelessWidget {
  const AuthContentWidth({super.key, required this.child});

  static const double maxWidth = 320;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
