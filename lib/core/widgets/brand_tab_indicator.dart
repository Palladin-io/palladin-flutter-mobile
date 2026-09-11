import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Active tab underline with the same brand tint as primary-button glow.
class BrandTabIndicator extends Decoration {
  const BrandTabIndicator({required this.glowColor});

  final Color glowColor;

  @override
  EdgeInsetsGeometry get padding =>
      const EdgeInsets.only(bottom: AppSpacing.xxs);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _BrandTabPainter(glowColor);
}

class _BrandTabPainter extends BoxPainter {
  _BrandTabPainter(this.glowColor);

  final Color glowColor;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    final line = RRect.fromRectAndRadius(
      Rect.fromLTWH(offset.dx, offset.dy + size.height - 2, size.width, 2),
      const Radius.circular(1),
    );
    canvas.drawRRect(
      line.inflate(1),
      Paint()
        ..color = glowColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawRRect(line, Paint()..color = AppColors.brandRed);
  }
}
