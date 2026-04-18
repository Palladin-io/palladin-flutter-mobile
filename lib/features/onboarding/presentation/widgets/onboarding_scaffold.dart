import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'onboarding_progress_dots.dart';

/// Common scaffold shared by all three onboarding screens.
///
/// Keeps the dark background, progress dots, title, subtitle, and
/// scrollable content area consistent across the wizard. Individual
/// screens pass their step-specific [children] in.
class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({
    super.key,
    required this.currentStep,
    required this.title,
    required this.subtitle,
    required this.children,
    this.footer,
    this.onBack,
  });

  final int currentStep;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? footer;
  /// When non-null, a back arrow is shown to the left of the progress dots.
  final VoidCallback? onBack;


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.darkBackgroundGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: onBack != null
                          ? GestureDetector(
                              onTap: onBack,
                              child: const Icon(
                                Icons.arrow_back_ios_new,
                                color: AppColors.textSecondary,
                                size: 18,
                              ),
                            )
                          : null,
                    ),
                    Expanded(
                      child: OnboardingProgressDots(currentStep: currentStep),
                    ),
                    const SizedBox(width: 28),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textTertiary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ),
                if (footer != null) ...[
                  const SizedBox(height: 12),
                  footer!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
