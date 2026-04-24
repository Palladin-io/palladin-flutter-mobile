/// Base class for all states of the account-recovery flow.
sealed class RecoveryState {
  const RecoveryState();
}

/// Idle — nothing in flight, no error.
final class RecoveryInitial extends RecoveryState {
  const RecoveryInitial();
}

/// An operation is running — either validating the recovery mnemonic
/// (step 1) or executing the full recovery pipeline (step 2).
///
/// Typically 300 ms – 2 s on mobile because each Argon2id derivation
/// takes a non-trivial amount of time.
final class RecoveryLoading extends RecoveryState {
  const RecoveryLoading();
}

/// Step 1 success — the supplied mnemonic opened
/// `encryptedPrivateKeyByRecovery`. The UI advances to step 2 where
/// the user sets a new master password.
///
/// Carries [validatedMnemonic] so step 2 can re-run the full pipeline
/// without asking the user to retype it.
final class RecoveryKeyValidated extends RecoveryState {
  const RecoveryKeyValidated({required this.validatedMnemonic});

  final String validatedMnemonic;
}

/// Step 2 success — the backend has been updated atomically with the
/// new salts and wrapped private keys. The UI shows the freshly
/// generated 24-word mnemonic so the user can back it up.
final class RecoveryCompleted extends RecoveryState {
  const RecoveryCompleted({required this.newRecoveryMnemonic});

  /// Space-separated 24-word mnemonic returned from the crypto service.
  /// Not the list variant — the UI needs to render per-word AND show
  /// copy-to-clipboard, so a single canonical string keeps both paths
  /// honest.
  final List<String> newRecoveryMnemonic;
}

/// Any failure from either step — wrong mnemonic, missing recovery
/// material, or network/server error. The presentation layer maps
/// [error] to a localized message via `AppLocalizations`.
final class RecoveryFailed extends RecoveryState {
  const RecoveryFailed(this.error);

  final Object error;
}
