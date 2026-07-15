import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Shared brand hero — the app logo above the "Palladin.io" wordmark.
///
/// Single source of the brand lockup so the login and unlock screens never
/// drift apart. "Palladin" renders in [textColor]; the ".io" suffix is always
/// [AppColors.brandRed]. Callers add their own subtitle below (login's rotating
/// welcome, unlock's "enter master password" hint) — the hero owns only the
/// logo + wordmark.
class BrandHero extends StatelessWidget {
  const BrandHero({
    super.key,
    required this.textColor,
    this.wordmarkFontSize = 28,
    this.logoWordmarkGap = AppSpacing.lg,
  });

  /// Color for the "Palladin" portion of the wordmark. Use [textColorFor] to
  /// derive it from the current [Brightness] consistently across screens.
  final Color textColor;

  /// Font size of the "Palladin.io" wordmark. Defaults to the shared size used
  /// across authentication and unlock screens.
  final double wordmarkFontSize;

  /// Vertical space between the logo asset and the wordmark.
  final double logoWordmarkGap;

  /// The wordmark text color for a given [brightness] — pure white on dark,
  /// the dark background tone on light. Centralised so both screens stay in
  /// sync.
  static Color textColorFor(Brightness brightness) =>
      brightness == Brightness.dark
      ? AppColors.onBrandRed
      : AppColors.darkBackground;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/images/logo.png', height: 64),
        SizedBox(height: logoWordmarkGap),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(
              fontSize: wordmarkFontSize,
              fontWeight: FontWeight.w800,
              height: 1.0,
              letterSpacing: wordmarkFontSize * -0.01,
            ),
            children: [
              TextSpan(
                text: 'Palladin',
                style: TextStyle(color: textColor),
              ),
              const TextSpan(
                text: '.io',
                style: TextStyle(color: AppColors.brandRed),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
