import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'brand_hero.dart';

/// Opaque brand cover shown over the app while backgrounded, so the OS
/// app-switcher snapshot masks any open vault or secret.
class PrivacyCover extends StatelessWidget {
  const PrivacyCover({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Positioned.fill(
      child: Material(
        color: AppColors.backgroundGradient(brightness).colors.first,
        child: Container(
          decoration: BoxDecoration(
            gradient: AppColors.backgroundGradient(brightness),
          ),
          alignment: Alignment.center,
          child: BrandHero(textColor: BrandHero.textColorFor(brightness)),
        ),
      ),
    );
  }
}
