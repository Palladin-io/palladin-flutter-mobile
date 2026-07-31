import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../core/crypto/sodium_provider.dart';
import '../../domain/unlock_exceptions.dart';
import 'identity_kdf_service.dart';

/// Result of a successful master-password unlock — the two pieces of
/// key material that downstream features (vault decryption, grant
/// approval, etc.) need in memory.
class UnlockResult {
  const UnlockResult({required this.masterKey, required this.privateKey});

  /// 32-byte Argon2id-derived master key.
  final Uint8List masterKey;

  /// 32-byte X25519 private key decrypted with [masterKey].
  final Uint8List privateKey;
}

/// Zero-knowledge crypto pipeline for the unlock flow.
///
/// Mirrors [OnboardingCryptoService] but in reverse:
/// 1. Derive the master key (MK) from the user's master password via
///    Argon2id using the salt returned by the backend.
/// 2. Split the base64-decoded ciphertext into `nonce || cipher`.
/// 3. Open the ciphertext with `crypto_secretbox_open_easy` to recover
///    the plaintext X25519 private key.
///
/// A failed decryption surfaces as [WrongMasterPasswordException] —
/// libsodium's MAC check is constant-time, so the caller should not
/// distinguish between "wrong password" and "tampered ciphertext".
class UnlockCryptoService {
  UnlockCryptoService({
    Future<SodiumSumo> Function()? sodiumLoader,
    IdentityKdfService? identityKdfService,
  }) : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance,
       _identityKdfService =
           identityKdfService ?? IdentityKdfService(sodiumLoader: sodiumLoader);

  final Future<SodiumSumo> Function() _sodiumLoader;
  final IdentityKdfService _identityKdfService;

  /// Derives the master key from [masterPassword] and [saltBase64],
  /// then decrypts [encryptedPrivateKeyBase64] with it.
  ///
  /// Throws [WrongMasterPasswordException] if decryption fails.
  Future<UnlockResult> deriveAndDecrypt({
    required String masterPassword,
    required String accountId,
    required IdentityKdfMetadata kdf,
    required String encryptedPrivateKeyBase64,
  }) async {
    _identityKdfService.assertSupported(kdf);
    final sodium = await _sodiumLoader();
    final salt = _decodeWireBytes(kdf.kdfSalt);
    IdentityKdfOutputs? outputs;
    SecureKey? masterKey;
    try {
      outputs = await _identityKdfService.derive(
        password: masterPassword,
        accountId: accountId,
        kdfSalt: salt,
      );
      masterKey = SecureKey.fromList(sodium, outputs.masterKey);
      final privateKeyBytes = _openPrivateKey(
        sodium,
        masterKey,
        encryptedPrivateKeyBase64,
      );

      // Copy the raw MK bytes into a detached Uint8List so the
      // presentation layer can hold them after we dispose the
      // SecureKey wrapper. `extractBytes()` already returns a copy
      // (not backed by the native buffer) so this is safe.
      return UnlockResult(
        masterKey: Uint8List.fromList(outputs.masterKey),
        privateKey: privateKeyBytes,
      );
    } finally {
      salt.fillRange(0, salt.length, 0);
      masterKey?.dispose();
      outputs?.dispose();
    }
  }

  /// Decrypts the private-key ciphertext using an already-derived
  /// master key — used by the biometric unlock path where the MK has
  /// been recovered from the OS keychain/keystore and there's no need
  /// to re-run Argon2id.
  ///
  /// Throws [WrongMasterPasswordException] if decryption fails (e.g.
  /// the backend ciphertext has rotated and the stashed MK is stale).
  Future<UnlockResult> decryptWithMasterKey({
    required Uint8List masterKey,
    required String encryptedPrivateKeyBase64,
  }) async {
    final sodium = await _sodiumLoader();
    final secureKey = SecureKey.fromList(sodium, masterKey);
    try {
      final privateKeyBytes = _openPrivateKey(
        sodium,
        secureKey,
        encryptedPrivateKeyBase64,
      );
      return UnlockResult(
        masterKey: Uint8List.fromList(masterKey),
        privateKey: privateKeyBytes,
      );
    } finally {
      secureKey.dispose();
    }
  }

  /// Splits the base64-decoded blob into `nonce || ciphertext` and
  /// runs `crypto_secretbox_open_easy` against [key].
  Uint8List _openPrivateKey(
    SodiumSumo sodium,
    SecureKey key,
    String encryptedPrivateKeyBase64,
  ) {
    final combined = _decodeWireBytes(encryptedPrivateKeyBase64);
    final nonceBytes = sodium.crypto.secretBox.nonceBytes;

    if (combined.length <= nonceBytes) {
      // Too short to contain both a nonce and an authenticated
      // ciphertext — treat as wrong-password for the user, the blob is
      // clearly not what the onboarding flow produced.
      throw const WrongMasterPasswordException();
    }

    final nonce = Uint8List.sublistView(combined, 0, nonceBytes);
    final cipher = Uint8List.sublistView(combined, nonceBytes);

    try {
      return sodium.crypto.secretBox.openEasy(
        cipherText: cipher,
        nonce: nonce,
        key: key,
      );
    } on SodiumException {
      throw const WrongMasterPasswordException();
    }
  }

  Uint8List _decodeWireBytes(String value) {
    try {
      return Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));
    } on FormatException {
      return Uint8List.fromList(base64.decode(value));
    }
  }
}
