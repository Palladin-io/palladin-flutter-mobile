import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Decorative layers stay centered on the shield, even as auth content scrolls.
class AuthShieldSurface extends StatelessWidget {
  const AuthShieldSurface({super.key, required this.child});
  final Widget child;

  static const double shieldHeight = 72;

  Widget _layer(double size, Widget layer) => Positioned(
    width: size,
    height: size,
    top: (shieldHeight - size) / 2,
    child: IgnorePointer(child: RepaintBoundary(child: layer)),
  );

  Widget _grain() => Image.asset(
    'assets/images/panel-grain.png',
    excludeFromSemantics: true,
    repeat: ImageRepeat.repeat,
    scale: 256 / 180,
    alignment: Alignment.topLeft,
  );

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final light = brightness == Brightness.light;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        if (light)
          _layer(
            1400,
            Opacity(
              opacity: 0.16,
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: AppColors.authGrainMask.createShader,
                child: _grain(),
              ),
            ),
          ),
        _layer(
          light ? 800 : 840,
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppColors.authShieldBloom(brightness),
            ),
          ),
        ),
        if (light)
          _layer(
            960,
            Opacity(
              opacity: 0.85,
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: AppColors.authWhiteGrainMask.createShader,
                child: ColorFiltered(
                  colorFilter: AppColors.authWhiteGrainFilter,
                  child: _grain(),
                ),
              ),
            ),
          ),
        child,
      ],
    );
  }
}
