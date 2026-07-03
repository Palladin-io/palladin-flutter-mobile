import 'dart:typed_data';

/// Localized copy for the OS biometric prompts.
///
/// The data/core layer has no [BuildContext], so the presentation layer
/// (which has `AppLocalizations`) constructs this and threads it down into
/// [BiometricKeyStore.enroll] / [BiometricKeyStore.unlockKey]. Keeping the
/// strings out of core preserves the zero-hardcoded-string rule.
class BiometricPromptCopy {
  const BiometricPromptCopy({
    required this.promptTitle,
    required this.enrollTitle,
    required this.accessTitle,
    required this.cancelLabel,
  });

  /// Android BiometricPrompt title (both enroll + access).
  final String promptTitle;

  /// iOS reason shown when writing/enrolling the key.
  final String enrollTitle;

  /// iOS reason shown when reading the key to unlock.
  final String accessTitle;

  /// Android negative-button label.
  final String cancelLabel;
}

/// Why a biometric-gated key operation could not complete.
enum BiometricAuthFailureReason {
  /// User dismissed the OS prompt (cancel / back).
  canceled,

  /// The OS reported an authentication failure or the sensor became
  /// unavailable mid-prompt.
  failed,

  /// Device can't perform a biometric-bound operation (no hardware, no
  /// enrolled biometric, passcode not set, or the enclave key was
  /// invalidated by a biometric-enrollment change).
  unavailable,
}

/// Thrown by [BiometricKeyStore] when a biometric-gated read/write fails
/// for a reason other than "nothing is enrolled".
class BiometricAuthException implements Exception {
  const BiometricAuthException(this.reason);

  final BiometricAuthFailureReason reason;

  @override
  String toString() => 'BiometricAuthException(${reason.name})';
}

/// Abstraction over an OS-enclave-backed, biometric-gated key store used to
/// stash the master key (MK) for the biometric-unlock shortcut.
///
/// Unlike raw `flutter_secure_storage`, an implementation MUST bind the
/// stored value to biometric presence at the OS layer — the wrapping key
/// lives in the Secure Enclave (iOS `SecAccessControl` `.biometryCurrentSet`)
/// / Android Keystore (`setUserAuthenticationRequired(true)` +
/// `setInvalidatedByBiometricEnrollment(true)`), so the MK cannot be read
/// without a fresh, successful biometric authentication — even on a
/// compromised/rooted device where the app sandbox is bypassed.
///
/// The abstraction keeps [UnlockCubit] and its tests independent of the
/// concrete native package.
abstract interface class BiometricKeyStore {
  /// Whether the device can store/read a key behind biometric auth right now
  /// (hardware present + at least one biometric enrolled + passcode set).
  Future<bool> canStore();

  /// Whether a master key has previously been enrolled for biometric unlock.
  ///
  /// Cheap, NON-prompting check — reads a plaintext marker, never the
  /// enclave-protected key, so it will not surface a biometric prompt.
  Future<bool> isEnrolled();

  /// Persists [masterKey] behind biometric-gated, enclave-bound storage.
  ///
  /// May surface a one-time OS biometric prompt on Android (writing with a
  /// user-authentication-required Keystore key requires a fresh auth). Throws
  /// [BiometricAuthException] if the user declines or the write fails.
  Future<void> enroll(Uint8List masterKey, BiometricPromptCopy copy);

  /// Reads the enrolled master key, triggering the OS biometric prompt.
  ///
  /// Returns `null` if nothing is enrolled. Throws [BiometricAuthException]
  /// when the user cancels or authentication fails.
  Future<Uint8List?> unlockKey(BiometricPromptCopy copy);

  /// Removes the enrolled key + marker (and any legacy raw key). Best-effort
  /// — never throws, never prompts.
  Future<void> clear();

  /// Deletes the pre-hardening raw master key (the CVT-199 legacy key written
  /// directly to `flutter_secure_storage`) if it is still present.
  ///
  /// Best-effort — never throws, never prompts. Independent of biometric
  /// availability: it MUST run even on devices that cannot store a
  /// biometric-gated key (`canStore() == false`), otherwise an upgrading user
  /// on a non-biometric device would keep the raw MK on disk until logout.
  /// A no-op once the legacy key is gone, so it is safe to call on every
  /// unlock.
  Future<void> purgeLegacyRawKey();
}
