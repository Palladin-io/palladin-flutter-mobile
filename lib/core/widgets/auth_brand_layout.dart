import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_colors.dart';
import 'brand_grain_surface.dart';

/// Shared authentication canvas; the hero anchors the light grain to its shield.
class AuthBrandBackground extends StatelessWidget {
  const AuthBrandBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: AppColors.authGradient(brightness)),
      child: Stack(
        children: [
          if (brightness == Brightness.dark)
            Positioned.fill(
              child: BrandGrainOverlay(
                grain: AppColors.onSurface(brightness).withValues(alpha: 0.065),
              ),
            ),
          child,
        ],
      ),
    );
  }
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
