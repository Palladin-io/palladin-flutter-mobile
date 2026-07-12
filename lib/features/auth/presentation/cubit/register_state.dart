import 'dart:typed_data';

/// Step of the registration wizard.
enum RegisterStep {
  /// Screen 1 — email + master password + confirmation.
  credentials,

  /// Screen 2 — view / back up the generated recovery mnemonic.
  recoveryKeyBackup,

  /// Screen 3 — confirm a few words from the mnemonic.
  recoveryKeyConfirm,

  /// Transient — crypto pipeline running + `POST /api/auth/register`
  /// in-flight.
  submitting,

  /// Registration succeeded — the app navigates to the verify-email gate.
  completed,
}

/// The freshly derived key material handed to `AuthBloc` after a
/// successful registration so the vault is unlocked immediately (the user
/// just chose the password). Held in memory only.
class RegisterUnlockKeys {
  const RegisterUnlockKeys({required this.masterKey, required this.privateKey});

  final Uint8List masterKey;
  final Uint8List privateKey;
}

/// State held by the registration wizard.
///
/// The email and mnemonic are kept **in memory only** — never persisted
/// (zero-knowledge). The master **password is deliberately NOT part of
/// this state** — it lives in a private field on `RegisterCubit` and is
/// dropped on completion, so it never sits in an observable (bloc-logged)
/// state object. The password only ever leaves the device as `authHash`.
class RegisterState {
  const RegisterState({
    this.step = RegisterStep.credentials,
    this.email = '',
    this.mnemonic = const <String>[],
    this.error,
    this.unlockKeys,
  });

  final RegisterStep step;
  final String email;
  final List<String> mnemonic;

  /// Typed exception when registration fails; the presentation layer maps
  /// it to localized copy.
  final Object? error;

  /// Set alongside [RegisterStep.completed] — the raw keys the page hands
  /// to `AuthBloc`.
  final RegisterUnlockKeys? unlockKeys;

  RegisterState copyWith({
    RegisterStep? step,
    String? email,
    List<String>? mnemonic,
    Object? error,
    bool clearError = false,
    RegisterUnlockKeys? unlockKeys,
    bool clearUnlockKeys = false,
  }) {
    return RegisterState(
      step: step ?? this.step,
      email: email ?? this.email,
      mnemonic: mnemonic ?? this.mnemonic,
      error: clearError ? null : (error ?? this.error),
      unlockKeys: clearUnlockKeys ? null : (unlockKeys ?? this.unlockKeys),
    );
  }
}
