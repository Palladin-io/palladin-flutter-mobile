import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// A row of three horizontal dots showing the current onboarding step.
///
/// Matches the `.progress-dots` pattern from the mobile prototype:
/// active step is shown in teal (accent), completed steps in muted teal,
/// and upcoming steps in a dimmed surface color.
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
          color = AppColors.tealAccent;
        } else if (isDone) {
          color = AppColors.tealAccent.withValues(alpha: 0.5);
        } else {
          color = Colors.white.withValues(alpha: 0.08);
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Container(
            width: isActive ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }),
    );
  }
}
