import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/repositories/onboarding_repository.dart';
import 'onboarding_state.dart';

export 'onboarding_state.dart';

/// Drives the 3-screen onboarding wizard.
///
/// Holds the chosen master password and the generated recovery
/// mnemonic **in memory only** for the duration of the flow — nothing
/// is persisted to disk. On successful `POST /api/account/setup` the
/// cubit transitions to [OnboardingStep.completed] so the router can
/// redirect to the authenticated home.
class OnboardingCubit extends Cubit<OnboardingState> {
  OnboardingCubit({required this.repository}) : super(const OnboardingState());

  final OnboardingRepository repository;

  /// Records the chosen master password and generates the recovery
  /// mnemonic in one step so the UI can move on to screen 2.
  Future<void> submitMasterPassword(String password) async {
    AppLogger.d('Onboarding', 'Master password submitted, generating mnemonic');
    final mnemonic = await repository.generateRecoveryMnemonic();
    emit(state.copyWith(
      step: OnboardingStep.recoveryKeyBackup,
      masterPassword: password,
      mnemonic: mnemonic,
      clearError: true,
    ));
  }

  /// Advances from the backup screen to the confirmation screen.
  void acknowledgeRecoveryBackup() {
    AppLogger.d('Onboarding', 'Recovery key backup acknowledged');
    emit(state.copyWith(
      step: OnboardingStep.recoveryKeyConfirm,
      clearError: true,
    ));
  }

  /// Runs the crypto pipeline, submits the setup request, and
  /// auto-creates the default vault.
  ///
  /// [defaultVaultName] is the localized vault name passed from the UI
  /// (e.g. `AppLocalizations.of(context)!.defaultVaultName`).
  ///
  /// On success: transitions to [OnboardingStep.completed].
  /// On failure: transitions back to [OnboardingStep.recoveryKeyConfirm]
  /// with an error attached so the UI can surface it.
  Future<void> completeSetup({required String defaultVaultName}) async {
    if (state.masterPassword.isEmpty || state.mnemonic.isEmpty) {
      AppLogger.w('Onboarding', 'Cannot complete setup — missing password/mnemonic');
      return;
    }

    emit(state.copyWith(
      step: OnboardingStep.submitting,
      clearError: true,
    ));

    try {
      final keys = await repository.completeSetup(
        masterPassword: state.masterPassword,
        recoveryMnemonic: state.mnemonic,
        defaultVaultName: defaultVaultName,
      );
      // Guard against a race where the user tapped back while the
      // setup request was in-flight — if we're no longer in the
      // submitting step, leave the current state alone.
      if (state.step != OnboardingStep.submitting) return;
      AppLogger.i('Onboarding', 'Setup completed successfully');
      emit(state.copyWith(step: OnboardingStep.completed, unlockKeys: keys));
    } on OnboardingAlreadyCompletedException {
      // The backend already has a setup for this account (409). The
      // repository has already flipped the local onboarded flag —
      // treat this as success and let the router forward the user on.
      if (state.step != OnboardingStep.submitting) return;
      AppLogger.i('Onboarding', 'Account already onboarded — treating as success');
      emit(state.copyWith(step: OnboardingStep.completed));
    } catch (e, s) {
      if (state.step != OnboardingStep.submitting) return;
      AppLogger.e('Onboarding', 'Setup failed', error: e, stackTrace: s);
      emit(state.copyWith(
        step: OnboardingStep.recoveryKeyConfirm,
        error: e,
      ));
    }
  }

  /// Drops the cubit's reference to the freshly derived unlock keys
  /// after the presentation layer has handed them to `AuthBloc`.
  ///
  /// The byte buffers are intentionally **not** zeroed here — the same
  /// references now live in `AuthAuthenticated` for the unlocked
  /// session, so zeroing them would wipe the live session keys. Dropping
  /// the reference just stops this (short-lived, factory-scoped) cubit
  /// from retaining a second handle to the key material.
  void clearUnlockKeys() {
    if (state.unlockKeys == null) return;
    emit(state.copyWith(clearUnlockKeys: true));
  }

  /// Goes back one step (used by system back-button handling on
  /// screens 2 and 3).
  void goBack() {
    switch (state.step) {
      case OnboardingStep.recoveryKeyBackup:
        emit(state.copyWith(
          step: OnboardingStep.masterPassword,
          clearError: true,
        ));
      case OnboardingStep.recoveryKeyConfirm:
        emit(state.copyWith(
          step: OnboardingStep.recoveryKeyBackup,
          clearError: true,
        ));
      case OnboardingStep.masterPassword:
      case OnboardingStep.submitting:
      case OnboardingStep.completed:
        break;
    }
  }
}
