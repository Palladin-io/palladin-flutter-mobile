import '../../domain/repositories/onboarding_repository.dart';

/// Current step of the onboarding wizard.
enum OnboardingStep {
  /// Screen 1 — user is choosing a master password.
  masterPassword,

  /// Screen 2 — user is viewing / backing up the recovery mnemonic.
  recoveryKeyBackup,

  /// Screen 3 — user is confirming 3 random words from the mnemonic.
  recoveryKeyConfirm,

  /// Transient state while the crypto pipeline runs and the setup
  /// request is in-flight.
  submitting,

  /// Setup completed successfully — the app should navigate to home.
  completed,
}

/// State held by [OnboardingCubit].
///
/// The master password and the mnemonic are kept **in memory only** —
/// they must never be written to disk (per zero-knowledge guarantees).
class OnboardingState {
  const OnboardingState({
    this.step = OnboardingStep.masterPassword,
    this.masterPassword = '',
    this.mnemonic = const <String>[],
    this.error,
    this.unlockKeys,
  });

  final OnboardingStep step;
  final String masterPassword;
  final List<String> mnemonic;

  /// Carries a typed exception when setup fails; the presentation layer
  /// maps it to a localized message.
  final Object? error;

  /// Set alongside [OnboardingStep.completed] on a fresh setup — the raw
  /// keys the presentation layer hands to `AuthBloc` so the vault is
  /// immediately unlocked. `null` on the "already onboarded" (409) path,
  /// where no fresh keys exist and the vault stays locked.
  final OnboardingUnlockKeys? unlockKeys;

  OnboardingState copyWith({
    OnboardingStep? step,
    String? masterPassword,
    List<String>? mnemonic,
    Object? error,
    bool clearError = false,
    OnboardingUnlockKeys? unlockKeys,
    bool clearUnlockKeys = false,
  }) {
    return OnboardingState(
      step: step ?? this.step,
      masterPassword: masterPassword ?? this.masterPassword,
      mnemonic: mnemonic ?? this.mnemonic,
      error: clearError ? null : (error ?? this.error),
      unlockKeys: clearUnlockKeys ? null : (unlockKeys ?? this.unlockKeys),
    );
  }
}
