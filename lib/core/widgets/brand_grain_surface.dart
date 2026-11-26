import 'dart:math' as math;
import 'dart:typed_data';
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
  static final ui.Image _tile = _makeTile();
  static final Float64List _identity = Float64List.fromList([
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
  ]);

  static ui.Image _makeTile() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawPoints(
      ui.PointMode.points,
      _makePoints(),
      Paint()
        ..color = AppColors.onBrandRed
        ..strokeWidth = 0.5,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(_tileSize.toInt(), _tileSize.toInt());
    picture.dispose();
    return image;
  }

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
    // Rasterize the decorative tile once; do not replay thousands of points
    // per tile on every route transition. This cache contains no user data.
    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.ImageShader(
          _tile,
          TileMode.repeated,
          TileMode.repeated,
          _identity,
        )
        ..colorFilter = ColorFilter.mode(grain, BlendMode.srcIn),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.Gradient.radial(
          origin,
          radius,
          [AppColors.onBrandRed, AppColors.onBrandRed.withValues(alpha: 0.1)],
          [0, 1],
        ),
    );
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrandGrainPainter oldDelegate) =>
      oldDelegate.grain != grain ||
      oldDelegate.bloom != bloom ||
      oldDelegate.centeredAtShield != centeredAtShield;
}
