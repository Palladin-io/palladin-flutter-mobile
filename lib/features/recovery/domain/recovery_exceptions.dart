/// Typed exceptions for the account-recovery flow.
///
/// Mirrors the pattern used by unlock/onboarding — no user-facing text
/// in the data/domain layer. The presentation layer maps these to
/// localized messages via `AppLocalizations`.
library;

/// Thrown when the recovery mnemonic supplied by the user fails to
/// decrypt `encryptedPrivateKeyByRecovery` (MAC check fails in
/// libsodium). This is the "wrong recovery key" signal.
class WrongRecoveryKeyException implements Exception {
  const WrongRecoveryKeyException();

  @override
  String toString() => 'WrongRecoveryKeyException';
}

/// Thrown when the backend account response is missing the recovery
/// material (`recoverySalt` or `encryptedPrivateKeyByRecovery`), which
/// means the account was provisioned before recovery was rolled out
/// and can't be recovered client-side.
class RecoveryMaterialMissingException implements Exception {
  const RecoveryMaterialMissingException();

  @override
  String toString() => 'RecoveryMaterialMissingException';
}

/// Thrown when the server's account-recovery challenge cannot be opened
/// as an `account-recovery-challenge-v1` package bound to the session user.
/// Deliberately carries no detail about which check failed.
class RecoveryChallengeException implements Exception {
  const RecoveryChallengeException();

  @override
  String toString() => 'RecoveryChallengeException';
}

/// Thrown when the recovery request fails for network/protocol reasons.
///
/// Carries a typed [kind] so the presentation layer can resolve the
/// appropriate localized message without embedding user-facing text in
/// the data layer.
class RecoveryServerException implements Exception {
  const RecoveryServerException(this.kind);

  final RecoveryServerErrorKind kind;

  @override
  String toString() => 'RecoveryServerException(${kind.name})';
}

/// Classifies server/network errors so the UI can map them to localized
/// strings.
enum RecoveryServerErrorKind {
  serverNotResponding,
  cannotConnect,
  connectionFailed,
  invalidResponse,

  /// `403 errors.backend.recovery-proof-invalid` — the one-time challenge
  /// proof was missing, wrong, expired or already used.
  recoveryProofInvalid,
}
