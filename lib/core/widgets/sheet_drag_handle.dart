import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// The 36×4 rounded pill shown at the top of a modal bottom sheet.
///
/// Canonical replacement for the ~17 inline copies scattered across the
/// sheets (approval, audit, grants…). New sheets should use this; the
/// existing inline copies can migrate to it opportunistically.
class SheetDragHandle extends StatelessWidget {
  const SheetDragHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.onSurfaceSubtle(brightness).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
