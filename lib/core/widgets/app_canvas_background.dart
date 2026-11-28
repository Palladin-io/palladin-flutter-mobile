import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'brand_grain_surface.dart';

/// Shared authenticated canvas; cards remain opaque above the texture.
class AppCanvasBackground extends StatelessWidget {
  const AppCanvasBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: AppColors.canvasGradient(brightness)),
      child: Stack(
        children: [
          Positioned.fill(
            child: BrandGrainOverlay(grain: AppColors.canvasGrain(brightness)),
          ),
          child,
        ],
      ),
    );
  }
}
