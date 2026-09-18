import 'package:flutter/material.dart';

import '../../../../core/widgets/app_brand_background.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../cubit/onboarding_cubit.dart';
import 'master_password_page.dart';
import 'recovery_key_backup_page.dart';
import 'recovery_key_confirm_page.dart';

/// Host for the 3-screen onboarding wizard.
///
/// Owns the [OnboardingCubit] for the duration of the flow and swaps
/// the child page based on the current [OnboardingStep]. On
/// [OnboardingStep.completed] it refreshes the auth state so the router
/// redirects to `/` (home).
class OnboardingWizardPage extends StatelessWidget {
  const OnboardingWizardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<OnboardingCubit>(
      create: (_) => getIt<OnboardingCubit>(),
      child: const _OnboardingWizardView(),
    );
  }
}

class _OnboardingWizardView extends StatelessWidget {
  const _OnboardingWizardView();

  @override
  Widget build(BuildContext context) {
    return BlocListener<OnboardingCubit, OnboardingState>(
      listenWhen: (p, c) =>
          p.step != c.step && c.step == OnboardingStep.completed,
      listener: (context, state) {
        // Hand the freshly derived keys to AuthBloc so the vault is
        // unlocked immediately — the user doesn't have to re-enter the
        // password they just set. On the "already onboarded" path the
        // keys are null and AuthBloc keeps the vault locked (→ /unlock).
        final keys = state.unlockKeys;
        context.read<AuthBloc>().add(
          OnboardingCompleted(
            masterKey: keys?.masterKey,
            privateKey: keys?.privateKey,
          ),
        );
        // Drop the cubit's now-redundant reference (AuthBloc owns the
        // live copies for the session).
        context.read<OnboardingCubit>().clearUnlockKeys();
      },
      child: BlocBuilder<OnboardingCubit, OnboardingState>(
        buildWhen: (p, c) => p.step != c.step || p.mnemonic != c.mnemonic,
        builder: (context, state) {
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              final cubit = context.read<OnboardingCubit>();
              switch (state.step) {
                case OnboardingStep.masterPassword:
                case OnboardingStep.submitting:
                case OnboardingStep.completed:
                  break;
                case OnboardingStep.recoveryKeyBackup:
                case OnboardingStep.recoveryKeyConfirm:
                  cubit.goBack();
              }
            },
            child: GestureDetector(
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity;
                if (velocity != null &&
                    velocity > 200 &&
                    (state.step == OnboardingStep.recoveryKeyBackup ||
                        state.step == OnboardingStep.recoveryKeyConfirm)) {
                  context.read<OnboardingCubit>().goBack();
                }
              },
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) {
                  final offset =
                      Tween<Offset>(
                        begin: const Offset(0.04, 0),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOut,
                        ),
                      );
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: offset, child: child),
                  );
                },
                child: KeyedSubtree(
                  // submitting → same screen as recoveryKeyConfirm; use one key
                  // to avoid a spurious animation when submit fires.
                  key: ValueKey(
                    state.step == OnboardingStep.submitting
                        ? OnboardingStep.recoveryKeyConfirm
                        : state.step,
                  ),
                  child: _pageForStep(state.step),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _pageForStep(OnboardingStep step) {
    switch (step) {
      case OnboardingStep.masterPassword:
        return const MasterPasswordPage();
      case OnboardingStep.recoveryKeyBackup:
        return const RecoveryKeyBackupPage();
      case OnboardingStep.recoveryKeyConfirm:
      case OnboardingStep.submitting:
        return const RecoveryKeyConfirmPage();
      case OnboardingStep.completed:
        // Router redirect fires on the auth-check — show a spinner as a
        // brief placeholder while the transition happens.
        return const _CompletedPlaceholder();
    }
  }
}

/// Brief gradient placeholder shown while the router redirects home after
/// onboarding completes. Matches the wizard's brightness-aware background
/// so light mode stays consistent (no flash of dark navy).
class _CompletedPlaceholder extends StatelessWidget {
  const _CompletedPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBrandBackground(
        showDarkGrain: true,
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
