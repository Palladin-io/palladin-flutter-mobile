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
  });

  final OnboardingStep step;
  final String masterPassword;
  final List<String> mnemonic;

  /// Carries a typed exception when setup fails; the presentation layer
  /// maps it to a localized message.
  final Object? error;

  OnboardingState copyWith({
    OnboardingStep? step,
    String? masterPassword,
    List<String>? mnemonic,
    Object? error,
    bool clearError = false,
  }) {
    return OnboardingState(
      step: step ?? this.step,
      masterPassword: masterPassword ?? this.masterPassword,
      mnemonic: mnemonic ?? this.mnemonic,
      error: clearError ? null : (error ?? this.error),
    );
  }
}
