import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../core/crypto/sodium_provider.dart';
import '../../domain/crypto_params.dart';
import '../../domain/repositories/onboarding_repository.dart';

/// Zero-knowledge crypto pipeline for the onboarding flow.
///
/// Responsibilities:
/// 1. Derive the master key (MK) from the user's master password via Argon2id.
/// 2. Derive the recovery key (RK) from the recovery mnemonic via Argon2id.
/// 3. Generate an X25519 keypair.
/// 4. Encrypt the private key with both MK and RK using
///    `crypto_secretbox_easy` (XSalsa20-Poly1305) with a prepended nonce.
///
/// No plaintext key material leaves this class — the returned
/// [OnboardingSetupPayload] contains only the salt, the public key,
/// and the two encrypted-private-key blobs.
class OnboardingCryptoService {
  OnboardingCryptoService({Future<SodiumSumo> Function()? sodiumLoader})
      : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  final Future<SodiumSumo> Function() _sodiumLoader;

  /// Runs the full key-derivation and encryption pipeline and returns
  /// the payload ready to be submitted to `POST /api/account/setup`.
  Future<OnboardingSetupPayload> buildSetupPayload({
    required String masterPassword,
    required List<String> recoveryMnemonic,
  }) async {
    final sodium = await _sodiumLoader();

    final salt = sodium.randombytes.buf(CryptoParams.saltLength);
    final recoverySalt = sodium.randombytes.buf(CryptoParams.saltLength);

    final masterKey = _deriveKey(sodium, masterPassword, salt);
    try {
      final recoveryKey = _deriveKey(
        sodium,
        recoveryMnemonic.join(' '),
        recoverySalt,
      );
      try {
        final keyPair = sodium.crypto.box.keyPair();
        try {
          final privateKeyBytes = keyPair.secretKey.extractBytes();
          try {
            final encryptedPrivateKey = _encryptWithKey(
              sodium,
              plaintext: privateKeyBytes,
              key: masterKey,
            );
            final encryptedPrivateKeyByRecovery = _encryptWithKey(
              sodium,
              plaintext: privateKeyBytes,
              key: recoveryKey,
            );

            return OnboardingSetupPayload(
              salt: salt,
              recoverySalt: recoverySalt,
              publicKey: Uint8List.fromList(keyPair.publicKey),
              encryptedPrivateKey: encryptedPrivateKey,
              encryptedPrivateKeyByRecovery: encryptedPrivateKeyByRecovery,
            );
          } finally {
            // Zeroize the plaintext private key bytes in memory — the
            // encrypted copies in the payload are the only thing that
            // should survive this method.
            privateKeyBytes.fillRange(0, privateKeyBytes.length, 0);
          }
        } finally {
          keyPair.dispose();
        }
      } finally {
        recoveryKey.dispose();
      }
    } finally {
      masterKey.dispose();
    }
  }

  /// Runs `crypto_pwhash` (Argon2id) with the project-wide cost
  /// parameters and returns a [SecureKey] backed by locked memory.
  ///
  /// The password is UTF-8 encoded so non-ASCII characters in a master
  /// password hash identically on mobile and web.
  SecureKey _deriveKey(SodiumSumo sodium, String password, Uint8List salt) {
    final utf8Bytes = utf8.encode(password);
    return sodium.crypto.pwhash.call(
      outLen: CryptoParams.derivedKeyLength,
      password: Int8List.fromList(utf8Bytes),
      salt: salt,
      opsLimit: CryptoParams.argon2OpsLimit,
      memLimit: CryptoParams.argon2MemLimit,
      alg: CryptoPwhashAlgorithm.argon2id13,
    );
  }

  /// Encrypts [plaintext] with `crypto_secretbox_easy` and returns a
  /// single byte blob of the form `nonce || ciphertext`, matching the
  /// format used by the web panel.
  Uint8List _encryptWithKey(
    SodiumSumo sodium, {
    required Uint8List plaintext,
    required SecureKey key,
  }) {
    final nonce = sodium.randombytes.buf(sodium.crypto.secretBox.nonceBytes);
    final cipher = sodium.crypto.secretBox.easy(
      message: plaintext,
      nonce: nonce,
      key: key,
    );

    final combined = Uint8List(nonce.length + cipher.length);
    combined.setRange(0, nonce.length, nonce);
    combined.setRange(nonce.length, combined.length, cipher);
    return combined;
  }

}
