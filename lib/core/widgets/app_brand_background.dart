import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'brand_grain_surface.dart';

/// Shared page background for authentication and authenticated screens.
///
/// It owns the regular app background plus the light bloom behind the brand
/// lockup. Keeping the bloom at screen level avoids clipped rectangular edges
/// when individual auth forms scroll.
class AppBrandBackground extends StatelessWidget {
  const AppBrandBackground({
    super.key,
    required this.child,
    this.lightPageGradient = AppColors.authLightPageGradient,
    this.lightLogoGlow = AppColors.authLightLogoGlow,
    this.showDarkGrain = false,
  });

  final Widget child;
  final RadialGradient lightPageGradient;
  final RadialGradient lightLogoGlow;
  final bool showDarkGrain;

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
                      child: DecoratedBox(
                        decoration: BoxDecoration(gradient: lightPageGradient),
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
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: lightLogoGlow),
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
            if (showDarkGrain && brightness == Brightness.dark)
              Positioned.fill(
                child: BrandGrainOverlay(grain: AppColors.darkAuthGrain),
              ),
            Positioned.fill(child: child),
          ],
        );
      },
    );
  }
}
