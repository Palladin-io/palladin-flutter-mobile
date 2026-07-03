import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'brand_hero.dart';

/// Opaque brand cover shown over the whole app while it is backgrounded
/// (CVT-214, part b).
///
/// Rendered on top of the navigator whenever the app is not in the
/// `resumed` lifecycle state, so the snapshot the OS captures for the
/// app-switcher / recents shows this cover instead of any open vault,
/// entry, or secret. It does NOT set `FLAG_SECURE` — manual screenshots
/// stay allowed by product decision; this only masks the background
/// snapshot.
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
