import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Separate, shadow-free navigation surface above the textured canvas.
class AppHeaderSurface extends StatelessWidget {
  const AppHeaderSurface({
    super.key,
    required this.child,
    this.showDivider = true,
  });

  final Widget child;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.navigationGradient(brightness),
        border: showDivider
            ? Border(
                bottom: BorderSide(color: AppColors.cardBorder(brightness)),
              )
            : null,
      ),
      child: child,
    );
  }
}
