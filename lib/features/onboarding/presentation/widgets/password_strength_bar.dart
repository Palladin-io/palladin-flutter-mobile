import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/password_strength.dart';

/// 4-segment strength meter shown below the master-password input.
///
/// Each segment lights up in the appropriate strength color as the
/// [strength] score increases from 0 ([PasswordStrength.tooShort]) to
/// 4 ([PasswordStrength.veryStrong]).
class PasswordStrengthBar extends StatelessWidget {
  const PasswordStrengthBar({super.key, required this.strength});

  final PasswordStrength strength;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 4,
      child: Row(
        children: List<Widget>.generate(4, (index) {
          final filled = index < strength.score;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: index == 3 ? 0 : AppSpacing.xs),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: filled
                      ? _colorFor(strength)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Color _colorFor(PasswordStrength strength) {
    return switch (strength) {
      PasswordStrength.tooShort => AppColors.brandRed,
      PasswordStrength.weak => AppColors.brandRed,
      PasswordStrength.fair => AppColors.strengthFair,
      PasswordStrength.strong => AppColors.positiveAccent,
      PasswordStrength.veryStrong => AppColors.positiveAccent,
    };
  }
}
