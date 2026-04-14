import 'dart:typed_data';

/// Contract for onboarding-related operations.
///
/// The repository lives entirely in the data layer except for this
/// interface, which keeps the presentation/domain layers independent
/// of libsodium and dio.
abstract class OnboardingRepository {
  /// Generates a fresh 24-word BIP-39 mnemonic used as the recovery key.
  Future<List<String>> generateRecoveryMnemonic();

  /// Derives the key material, encrypts the private key with both the
  /// master key and the recovery key, and submits the bundle to
  /// `POST /api/account/setup`.
  ///
  /// Throws [OnboardingServerException] on network/protocol errors,
  /// [OnboardingAlreadyCompletedException] if the account is already
  /// set up (HTTP 409).
  Future<void> completeSetup({
    required String masterPassword,
    required List<String> recoveryMnemonic,
  });
}

/// Thrown when the backend rejects the setup because the account has
/// already been onboarded (HTTP 409).
class OnboardingAlreadyCompletedException implements Exception {
  @override
  String toString() => 'Account setup has already been completed';
}

/// Thrown when setup fails due to network/protocol errors.
///
/// Carries a typed [kind] so the presentation layer can resolve the
/// appropriate localized message.
class OnboardingServerException implements Exception {
  const OnboardingServerException(this.kind);

  final OnboardingServerErrorKind kind;

  @override
  String toString() => 'OnboardingServerException(${kind.name})';
}

/// Classifies server/network errors so the UI can map them to
/// localized strings without embedding user-facing text in the data layer.
enum OnboardingServerErrorKind {
  serverNotResponding,
  cannotConnect,
  connectionFailed,
  invalidResponse,
}

/// Small value object carrying the raw bytes needed to submit a setup
/// request. Exposed publicly so unit tests can verify the crypto
/// pipeline end-to-end.
///
/// The salts are kept as two separate fields: [salt] is used to derive
/// the master key from the master password, [recoverySalt] to derive
/// the recovery key from the mnemonic. Backend stores and returns them
/// independently.
class OnboardingSetupPayload {
  const OnboardingSetupPayload({
    required this.salt,
    required this.recoverySalt,
    required this.publicKey,
    required this.encryptedPrivateKey,
    required this.encryptedPrivateKeyByRecovery,
  });

  final Uint8List salt;
  final Uint8List recoverySalt;
  final Uint8List publicKey;
  final Uint8List encryptedPrivateKey;
  final Uint8List encryptedPrivateKeyByRecovery;
}
