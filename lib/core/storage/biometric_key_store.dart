import 'dart:typed_data';

/// Localized OS biometric-prompt strings, built in the presentation layer and
/// threaded into core (which has no [BuildContext]).
class BiometricPromptCopy {
  const BiometricPromptCopy({
    required this.promptTitle,
    required this.enrollTitle,
    required this.accessTitle,
    required this.cancelLabel,
  });

  final String promptTitle;
  final String enrollTitle;
  final String accessTitle;
  final String cancelLabel;
}

enum BiometricAuthFailureReason {
  /// User dismissed the OS prompt.
  canceled,

  /// Authentication failed or the sensor became unavailable mid-prompt.
  failed,

  /// Device can't do a biometric-bound operation, or the enclave key was
  /// invalidated by a biometric-enrollment change.
  unavailable,
}

class BiometricAuthException implements Exception {
  const BiometricAuthException(this.reason);

  final BiometricAuthFailureReason reason;

  @override
  String toString() => 'BiometricAuthException(${reason.name})';
}

/// OS-protected master-key copy used only after biometric authorization.
/// The key enters process memory after unlock; this is not protection against
/// a compromised OS or a compromised running application.
abstract interface class BiometricKeyStore {
  /// Incremented synchronously whenever cleanup is requested.
  int get generation;

  /// Whether the device can store/read a key behind biometric auth right now.
  Future<bool> canStore();

  /// Whether an MK has been enrolled. Cheap, non-prompting marker read.
  Future<bool> isEnrolled();

  /// Enrolls [masterKey] behind biometric-gated storage. Throws
  /// [BiometricAuthException] if the user declines or the write fails.
  Future<void> enroll(
    Uint8List masterKey,
    BiometricPromptCopy copy, {
    required int expectedGeneration,
  });

  /// Reads the enrolled MK via the OS biometric prompt. `null` if none
  /// enrolled; throws [BiometricAuthException] on cancel/failure.
  Future<Uint8List?> unlockKey(BiometricPromptCopy copy);

  /// Removes protected material and marker without requesting authentication.
  /// Throws [BiometricKeyCleanupException] if protected deletion fails.
  Future<void> clear();

  /// Deletes any pre-hardening raw MK still on disk. Best-effort; must run even
  /// when [canStore] is false, else a non-biometric device keeps the raw MK.
  Future<void> purgeLegacyRawKey();
}

/// Protected material could not be confirmed deleted by the platform.
class BiometricKeyCleanupException implements Exception {
  const BiometricKeyCleanupException();
}
