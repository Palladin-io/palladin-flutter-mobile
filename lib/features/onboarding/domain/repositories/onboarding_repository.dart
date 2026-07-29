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
  /// master key and the recovery key, submits the bundle to
  /// `POST /api/account/setup`, and then auto-creates the default vault
  /// via `POST /api/account/default-vault`.
  ///
  /// [defaultVaultName] is the localized vault name (e.g. "Personal" /
  /// "Osobisty") supplied by the presentation layer so the data layer
  /// has no dependency on BuildContext.
  ///
  /// Throws [OnboardingServerException] on network/protocol errors,
  /// [OnboardingAlreadyCompletedException] if the account is already
  /// set up (HTTP 409). The default-vault call is fire-and-forget: a
  /// 409 (already exists) or any transient error is swallowed so it
  /// never blocks the user from completing onboarding.
  ///
  /// On success returns the freshly derived [OnboardingUnlockKeys] so
  /// the presentation layer can seed the unlocked session — the user
  /// just set their master password, so there is no need to re-derive
  /// the keys via the unlock screen. The caller takes ownership of the
  /// returned key bytes and is responsible for their lifetime.
  Future<OnboardingUnlockKeys> completeSetup({
    required String masterPassword,
    required List<String> recoveryMnemonic,
    required String defaultVaultName,
  });
}

/// The raw key material derived during onboarding, handed to the auth
/// layer so the vault is immediately unlocked after setup.
///
/// Both fields are 32-byte buffers held **in memory only**. They mirror
/// exactly what a successful master-password unlock produces
/// (`UnlockSuccess`), and are consumed identically — carried into
/// `AuthAuthenticated` for the duration of the session.
class OnboardingUnlockKeys {
  const OnboardingUnlockKeys({
    required this.masterKey,
    required this.privateKey,
  });

  /// 32-byte master key derived from the master password via Argon2id.
  final Uint8List masterKey;

  /// 32-byte X25519 private key generated during setup.
  final Uint8List privateKey;
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
    required this.authCredential,
    required this.salt,
    required this.recoverySalt,
    required this.publicKey,
    required this.encryptedPrivateKey,
    required this.encryptedPrivateKeyByRecovery,
  });

  final Uint8List authCredential;
  final Uint8List salt;
  final Uint8List recoverySalt;
  final Uint8List publicKey;
  final Uint8List encryptedPrivateKey;
  final Uint8List encryptedPrivateKeyByRecovery;
}

/// Result of the onboarding crypto pipeline: the network-bound
/// [payload] plus the raw [masterKey] and [privateKey] retained so the
/// session can be unlocked immediately after setup.
///
/// The raw keys are the **only** plaintext key material to leave
/// [OnboardingCryptoService]; every other intermediate (recovery key,
/// the plaintext used to build the encrypted blobs) is zeroed inside
/// the service. The caller owns [masterKey] / [privateKey] and must
/// zero them if it does not hand them off to the auth layer.
class OnboardingSetupResult {
  const OnboardingSetupResult({
    required this.payload,
    required this.masterKey,
    required this.privateKey,
  });

  final OnboardingSetupPayload payload;
  final Uint8List masterKey;
  final Uint8List privateKey;
}
