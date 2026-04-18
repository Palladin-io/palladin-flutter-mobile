/// Thrown when the master password supplied to the unlock flow fails
/// to decrypt the private-key ciphertext (i.e. wrong password).
///
/// Modelled as a typed exception so the presentation layer can map it
/// to a localized string without carrying user-facing text into the
/// data layer.
class WrongMasterPasswordException implements Exception {
  const WrongMasterPasswordException();

  @override
  String toString() => 'WrongMasterPasswordException';
}

/// Thrown when the account endpoint fails for network/protocol reasons.
///
/// Carries a typed [kind] so the presentation layer can resolve the
/// appropriate localized message.
class UnlockServerException implements Exception {
  const UnlockServerException(this.kind);

  final UnlockServerErrorKind kind;

  @override
  String toString() => 'UnlockServerException(${kind.name})';
}

/// Classifies server/network errors so the UI can map them to
/// localized strings without embedding user-facing text in the data
/// layer.
enum UnlockServerErrorKind {
  serverNotResponding,
  cannotConnect,
  connectionFailed,
  invalidResponse,
}

/// Thrown when biometric unlock is attempted but no master key has
/// been persisted to secure storage yet (user has never unlocked via
/// password on this device).
class BiometricKeyMissingException implements Exception {
  const BiometricKeyMissingException();

  @override
  String toString() => 'BiometricKeyMissingException';
}

/// Thrown when biometric authentication is refused or cancelled by the
/// platform (user cancelled, failed the prompt, or the device is not
/// enrolled).
class BiometricAuthFailedException implements Exception {
  const BiometricAuthFailedException();

  @override
  String toString() => 'BiometricAuthFailedException';
}
