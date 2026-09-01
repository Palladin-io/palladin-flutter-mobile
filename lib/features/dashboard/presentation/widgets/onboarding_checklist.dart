import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/compact_primary_button.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/onboarding_status.dart';

/// The four-step "Set up Palladin" checklist shown to new users on the
/// dashboard until setup completes (or the user skips it).
///
/// Step 1 (notifications) is client-side and offers Enable / Skip. Steps
/// 2–4 (vault, API key, agent) each expose a CTA when they become the
/// active step; completed steps dim and show a check, future steps dim
/// progressively.
class OnboardingChecklist extends StatelessWidget {
  const OnboardingChecklist({
    super.key,
    required this.status,
    required this.notificationStepDone,
    required this.notificationPermissionDenied,
    required this.onSkipSetup,
    required this.onEnableNotifications,
    required this.onSkipNotification,
    required this.onVaultCta,
    required this.onApiKeyCta,
    required this.onAgentCta,
  });

  final OnboardingStatus status;
  final bool notificationStepDone;

  /// `true` when the OS permission was denied and the native prompt won't
  /// appear again. Changes the step-1 button from "Enable" to "Open Settings".
  final bool notificationPermissionDenied;

  final VoidCallback onSkipSetup;
  final VoidCallback onEnableNotifications;
  final VoidCallback onSkipNotification;
  final VoidCallback onVaultCta;
  final VoidCallback onApiKeyCta;
  final VoidCallback onAgentCta;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final dones = <bool>[
      notificationStepDone,
      status.entryCreated,
      status.apiKeyCreated,
      status.agentEnrolled,
    ];
    final completed = dones.where((d) => d).length;
    // First incomplete step (0-based). -1 means everything is done.
    final activeIndex = dones.indexWhere((d) => !d);

    final steps = <_StepData>[
      _StepData(
        number: 1,
        icon: Icons.notifications_active,
        accent: AppColors.onboardingStepAmber,
        title: l10n.dashboardOnboardingStep1Title,
        description: l10n.dashboardOnboardingStep1Description,
      ),
      _StepData(
        number: 2,
        icon: Icons.lock_open,
        accent: AppColors.vaultBlue,
        title: l10n.dashboardOnboardingStep2Title,
        description: l10n.dashboardOnboardingStep2Description,
        ctaLabel: l10n.dashboardOnboardingStep2Cta,
        onCta: onVaultCta,
      ),
      _StepData(
        number: 3,
        icon: Icons.key,
        accent: AppColors.agentPurple,
        title: l10n.dashboardOnboardingStep3Title,
        description: l10n.dashboardOnboardingStep3Description,
        ctaLabel: l10n.dashboardOnboardingStep3Cta,
        onCta: onApiKeyCta,
      ),
      _StepData(
        number: 4,
        icon: Icons.smart_toy,
        accent: AppColors.approveGreen,
        title: l10n.dashboardOnboardingStep4Title,
        description: l10n.dashboardOnboardingStep4Description,
        ctaLabel: l10n.dashboardOnboardingStep4Cta,
        onCta: onAgentCta,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProgressCard(completed: completed, onSkipSetup: onSkipSetup),
        const SizedBox(height: AppSpacing.fieldGap),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == steps.length - 1 ? 0 : AppSpacing.innerGap,
            ),
            child: _StepCard(
              step: steps[i],
              done: dones[i],
              isActive: i == activeIndex,
              opacity: _stepOpacity(
                index: i,
                done: dones[i],
                activeIndex: activeIndex,
              ),
              notificationPermissionDenied: i == 0
                  ? notificationPermissionDenied
                  : false,
              onEnableNotifications: onEnableNotifications,
              onSkipNotification: onSkipNotification,
            ),
          ),
      ],
    );
  }

  /// Done steps sit at 0.6; the active step is fully opaque; future steps
  /// dim progressively (0.6 → 0.45 → 0.3) the further they are from active.
  double _stepOpacity({
    required int index,
    required bool done,
    required int activeIndex,
  }) {
    if (done) return 0.6;
    if (index == activeIndex || activeIndex == -1) return 1;
    final distance = index - activeIndex;
    return (0.6 - (distance - 1) * 0.15).clamp(0.3, 0.6);
  }
}

/// Immutable descriptor for one checklist step.
class _StepData {
  const _StepData({
    required this.number,
    required this.icon,
    required this.accent,
    required this.title,
    required this.description,
    this.ctaLabel,
    this.onCta,
  });

  final int number;
  final IconData icon;
  final Color accent;
  final String title;
  final String description;
  final String? ctaLabel;
  final VoidCallback? onCta;
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.completed, required this.onSkipSetup});

  final int completed;
  final VoidCallback onSkipSetup;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.dashboardOnboardingTitle,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.innerGap),
          Text(
            l10n.dashboardOnboardingSubtitle,
            style: TextStyle(
              color: AppColors.onSurfaceSubtle(brightness),
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.innerGap),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: completed / 4,
              minHeight: 4,
              backgroundColor: AppColors.textTertiary.withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.brandRed,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.innerGap),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.dashboardOnboardingProgress(completed),
                style: TextStyle(
                  color: AppColors.onSurfaceSubtle(brightness),
                  fontSize: 12,
                ),
              ),
              GestureDetector(
                onTap: onSkipSetup,
                child: Text(
                  l10n.dashboardOnboardingSkipSetup,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.done,
    required this.isActive,
    required this.opacity,
    required this.notificationPermissionDenied,
    required this.onEnableNotifications,
    required this.onSkipNotification,
  });

  final _StepData step;
  final bool done;
  final bool isActive;
  final double opacity;

  /// Only relevant for step 1 (notifications). When `true`, the "Enable"
  /// button is replaced by "Open Settings".
  final bool notificationPermissionDenied;

  final VoidCallback onEnableNotifications;
  final VoidCallback onSkipNotification;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: BoxDecoration(
          color: AppColors.cardFill(brightness),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive
                ? step.accent.withValues(alpha: 0.3)
                : AppColors.cardBorder(brightness),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StepIcon(icon: step.icon, accent: step.accent),
            const SizedBox(width: AppSpacing.cardGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          step.title,
                          style: TextStyle(
                            color: AppColors.onSurface(brightness),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.innerGap),
                      if (done)
                        const Icon(
                          Icons.check_circle,
                          size: 16,
                          color: AppColors.positiveAccent,
                        )
                      else
                        _StepBadge(number: step.number, isActive: isActive),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.innerGap),
                  Text(
                    step.description,
                    style: TextStyle(
                      color: AppColors.onSurfaceSubtle(brightness),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  if (isActive && step.number == 1) ...[
                    const SizedBox(height: AppSpacing.fieldGap),
                    _NotificationActions(
                      onEnable: onEnableNotifications,
                      onSkip: onSkipNotification,
                      isDenied: notificationPermissionDenied,
                    ),
                  ] else if (isActive &&
                      step.ctaLabel != null &&
                      step.onCta != null) ...[
                    const SizedBox(height: AppSpacing.fieldGap),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: CompactPrimaryButton(
                        label: step.ctaLabel!,
                        onPressed: step.onCta!,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.icon, required this.accent});

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 16, color: accent),
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({required this.number, required this.isActive});

  final int number;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = isActive
        ? AppColors.onboardingStepAmber
        : AppColors.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.chipGap,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isActive ? 0.15 : 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        l10n.dashboardOnboardingStep(number),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _NotificationActions extends StatelessWidget {
  const _NotificationActions({
    required this.onEnable,
    required this.onSkip,
    required this.isDenied,
  });

  final VoidCallback onEnable;
  final VoidCallback onSkip;

  /// When `true`, the primary button shows "Open Settings" instead of "Enable"
  /// because the OS will no longer show the native permission prompt.
  final bool isDenied;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Row(
      children: [
        CompactPrimaryButton(
          label: isDenied
              ? l10n.dashboardOnboardingStep1OpenSettings
              : l10n.dashboardOnboardingStep1Enable,
          onPressed: onEnable,
          backgroundColor: AppColors.onboardingStepAmber,
          foregroundColor: AppColors.darkBackground,
        ),
        const SizedBox(width: AppSpacing.chipGap),
        OutlinedButton(
          onPressed: onSkip,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.onSurfaceSubtle(brightness),
            side: BorderSide(
              color: AppColors.onSurfaceSubtle(
                brightness,
              ).withValues(alpha: 0.25),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.fieldGap,
              vertical: AppSpacing.chipGap,
            ),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            l10n.dashboardOnboardingStep1Skip,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
