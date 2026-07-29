import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// A row of three circular dots showing the current onboarding step.
///
/// Matches the `.progress-dots / .dot` pattern from the mobile prototype:
/// active step → brandRed (#EB4747), completed steps → doneDot (#FFAB87),
/// upcoming steps → dimmed warm-white at 8 % opacity.
class OnboardingProgressDots extends StatelessWidget {
  const OnboardingProgressDots({
    super.key,
    required this.currentStep,
    this.totalSteps = 3,
  });

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(totalSteps, (index) {
        final isActive = index == currentStep;
        final isDone = index < currentStep;

        final Color color;
        if (isActive) {
          color = AppColors.brandRed;
        } else if (isDone) {
          color = AppColors.doneDot;
        } else {
          // Upcoming step — warm-white (textPrimary) at 8% opacity.
          color = AppColors.textPrimary.withValues(alpha: 0.08);
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        );
      }),
    );
  }
}
