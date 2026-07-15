import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/brand_hero.dart';
import '../../../../l10n/generated/app_localizations.dart';
import 'rotating_welcome.dart';

/// Shared brand lockup used by the authentication entry, sign-in, and
/// registration screens so its logo, wordmark, and copy never drift apart.
class AuthBrandHeader extends StatelessWidget {
  const AuthBrandHeader({
    super.key,
    this.topSpacing = defaultTopSpacing,
    this.caption,
  });

  /// Fixed distance below the safe area shared by every auth and
  /// confirmation screen. Keeping this explicit prevents a form's intrinsic
  /// height from moving the lockup inside an [AnimatedSwitcher].
  static const double defaultTopSpacing = AppSpacing.xxxl * 3;

  /// Canonical distance from the bottom of the brand lockup to the first
  /// control on authentication forms. The method picker, e-mail sign-in, and
  /// e-mail registration all use this value so their controls never jump.
  static const double formTopSpacing = AppSpacing.xxxl * 4 + AppSpacing.sm;

  /// Starts a labelled field early enough that the field border, rather than
  /// its label, aligns with the method picker's first button.
  static const double labelledFormTopSpacing = formTopSpacing - AppSpacing.xxl;

  /// Tighter start for dense auth forms that must fit three fields and their
  /// supporting actions without pushing essential copy below the fold.
  static const double denseFormTopSpacing =
      formTopSpacing - AppSpacing.xxxl * 2 - AppSpacing.sm;

  final double topSpacing;

  /// Replaces the rotating authentication copy with one persistent caption
  /// while preserving the shared lockup's exact height and spacing.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandHero(textColor: BrandHero.textColorFor(brightness)),
        const SizedBox(height: AppSpacing.lg),
        RotatingWelcome(
          messages: caption != null
              ? [caption!]
              : [
                  l10n.loginRotatingZeroKnowledge,
                  l10n.loginRotatingForAgents,
                  l10n.loginRotatingYourKeys,
                  l10n.loginRotatingEncrypted,
                ],
          textColor: AppColors.onSurfaceSubtle(brightness),
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.only(top: topSpacing),
      child: content,
    );
  }
}
