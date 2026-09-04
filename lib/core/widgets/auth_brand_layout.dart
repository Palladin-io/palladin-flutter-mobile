import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Shared visual frame for authentication and account-confirmation screens.
///
/// It owns the regular app background plus the light bloom behind the brand
/// lockup. Keeping the bloom at screen level avoids clipped rectangular edges
/// when individual auth forms scroll.
class AuthBrandBackground extends StatelessWidget {
  const AuthBrandBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final viewportHeight = constraints.maxHeight;
        final landingGlowHeight = viewportHeight * 2.2 > 1800
            ? viewportHeight * 2.2
            : 1800.0;

        return Stack(
          children: [
            Positioned.fill(
              child: brightness == Brightness.light
                  ? Transform.scale(
                      key: const ValueKey('auth-light-page-gradient'),
                      scaleX: 2.5,
                      scaleY: viewportHeight * 2 / viewportWidth,
                      alignment: AppColors.authLightPageCenter,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppColors.authLightPageGradient,
                        ),
                      ),
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppColors.backgroundGradient(brightness),
                      ),
                    ),
            ),
            if (brightness == Brightness.light)
              Positioned.fill(
                child: Transform.scale(
                  key: const ValueKey('auth-light-logo-glow'),
                  scaleX: 1.38,
                  scaleY: landingGlowHeight / viewportWidth,
                  alignment: AppColors.authLightGlowCenter,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppColors.authLightLogoGlow,
                    ),
                  ),
                ),
              ),
            if (brightness == Brightness.dark)
              Positioned(
                top: 0,
                right: 0,
                left: 0,
                height: AppSpacing.xxxl * 12,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppColors.darkAuthBrandGlow,
                    ),
                  ),
                ),
              ),
            Positioned.fill(child: child),
          ],
        );
      },
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
