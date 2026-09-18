import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Opaque navigation surface with static, neutral grain beneath its content.
class BrandGrainSurface extends StatelessWidget {
  const BrandGrainSurface({
    super.key,
    required this.backgroundColor,
    required this.child,
    this.subtle = false,
  });

  final Color backgroundColor;
  final Widget child;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final grain = AppColors.navigationGrain(brightness);
    return DecoratedBox(
      decoration: BoxDecoration(color: backgroundColor),
      child: Stack(
        children: [
          Positioned.fill(
            child: BrandGrainOverlay(
              grain: subtle ? grain.withValues(alpha: grain.a * 0.55) : grain,
              bloom: AppColors.navigationBloom(brightness),
              centeredAtShield: !subtle,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class BrandGrainOverlay extends StatelessWidget {
  const BrandGrainOverlay({
    super.key,
    required this.grain,
    this.bloom = AppColors.transparent,
    this.centeredAtShield = false,
  });

  final Color grain;
  final Color bloom;
  final bool centeredAtShield;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        painter: _BrandGrainPainter(
          grain: grain,
          bloom: bloom,
          centeredAtShield: centeredAtShield,
        ),
      ),
    ),
  );
}

class _BrandGrainPainter extends CustomPainter {
  const _BrandGrainPainter({
    required this.grain,
    required this.bloom,
    required this.centeredAtShield,
  });

  final Color grain;
  final Color bloom;
  final bool centeredAtShield;
  static const double _tileSize = 128;
  // Generated once, independent of credentials and application state.
  static final List<Offset> _points = _makePoints();

  static List<Offset> _makePoints() {
    final random = math.Random(42);
    return List.generate(
      5000,
      (_) => Offset(
        random.nextDouble() * _tileSize,
        random.nextDouble() * _tileSize,
      ),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRect(bounds);
    // The navbar light originates exactly below the centered shield, then
    // dissolves across the bar. The drawer gets a broader, quieter wash.
    final origin = Offset(size.width / 2, 0);
    final radius = centeredAtShield ? size.width * 0.55 : size.longestSide;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.radial(
          origin,
          radius,
          [
            centeredAtShield ? bloom : bloom.withValues(alpha: bloom.a * 0.5),
            AppColors.transparent,
          ],
          [0, 1],
        ),
    );
    final paint = Paint()..strokeWidth = 0.5;
    for (double y = 0; y < size.height; y += _tileSize) {
      for (double x = 0; x < size.width; x += _tileSize) {
        canvas.save();
        canvas.translate(x, y);
        paint.shader = ui.Gradient.radial(
          origin - Offset(x, y),
          radius,
          [grain, grain.withValues(alpha: grain.a * 0.1)],
          [0, 1],
        );
        canvas.drawPoints(ui.PointMode.points, _points, paint);
        canvas.restore();
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrandGrainPainter oldDelegate) =>
      oldDelegate.grain != grain ||
      oldDelegate.bloom != bloom ||
      oldDelegate.centeredAtShield != centeredAtShield;
}
