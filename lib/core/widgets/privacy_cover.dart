import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'brand_hero.dart';
import 'auth_brand_layout.dart';

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
        child: AuthBrandBackground(
          child: Center(
            child: BrandHero(textColor: BrandHero.textColorFor(brightness)),
          ),
        ),
      ),
    );
  }
}
