import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Decorative shadow only: the child retains its own hit target and states.
class PrimaryButtonGlow extends StatelessWidget {
  const PrimaryButtonGlow({
    super.key,
    required this.child,
    required this.enabled,
    this.radius = 10,
  });

  final Widget child;
  final bool enabled;
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: enabled
          ? [
              BoxShadow(
                color: AppColors.primaryGlow(Theme.of(context).brightness),
                blurRadius: 18,
                offset: const Offset(0, 5),
              ),
            ]
          : null,
    ),
    child: child,
  );
}
