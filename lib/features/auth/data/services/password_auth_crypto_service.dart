import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../core/crypto/sodium_provider.dart';
import '../../../onboarding/domain/crypto_params.dart';

/// Zero-knowledge crypto pipeline for the email + master-password auth
/// flow (Variant A).
///
/// The login password **is** the master password. From that single
/// secret the client runs **two independent Argon2id derivations** with
/// two independent salts:
///
///   * `authHash = Argon2id(password, authSalt)` — sent to the server as
///     the login credential. The server re-hashes it at rest.
///   * `MK       = Argon2id(password, encSalt)`  — **never leaves the
///     device**; unwraps the X25519 private key.
///
/// Because `authSalt != encSalt`, the value sent to the server
/// (`authHash`) reveals nothing about `MK`: they are pre-images of two
/// separate Argon2id evaluations. The server never sees the password,
/// `MK`, or the plaintext private key.
///
/// All key material is UTF-8 encoded before hashing so a non-ASCII
/// master password hashes identically on mobile and web. Every derived
/// [SecureKey] is disposed and every plaintext buffer is zeroed before a
/// method returns; only the deliberately retained `MK`/private-key
/// copies on [RegistrationCryptoMaterial] survive, and the caller owns
/// their lifetime.
class PasswordAuthCryptoService {
  PasswordAuthCryptoService({Future<SodiumSumo> Function()? sodiumLoader})
      : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  final Future<SodiumSumo> Function() _sodiumLoader;

  /// Derives the **auth hash** for `POST /api/auth/login` from
  /// [password] and the server-provided [authSaltBase64].
  ///
  /// Returns the base64-encoded Argon2id output. This is the only value
  /// derived from the password that ever leaves the device on the login
  /// path — it is a separate derivation from the master key and cannot
  /// be used to recover it.
  Future<String> deriveAuthHash({
    required String password,
    required String authSaltBase64,
  }) async {
    final sodium = await _sodiumLoader();
    final authSalt = base64.decode(authSaltBase64);
    final authKey = _deriveKey(sodium, password, authSalt);
    try {
      return base64.encode(authKey.extractBytes());
    } finally {
      authKey.dispose();
    }
  }

  /// Builds the full registration payload for `POST /api/auth/register`.
  ///
  /// Generates two independent salts ([RegistrationCryptoMaterial.authSalt]
  /// and [RegistrationCryptoMaterial.encSalt]), an X25519 keypair, then:
  ///   1. derives `authHash` from `password + authSalt`,
  ///   2. derives `MK`      from `password + encSalt`,
  ///   3. derives `RK`      from `mnemonic + recoverySalt`,
  ///   4. wraps the private key under both `MK` and `RK`.
  ///
  /// Retains the raw `MK` and private key on the result so the caller can
  /// seed an unlocked session immediately after registration (the user
  /// just chose the password — no need to re-derive on an unlock screen).
  Future<RegistrationCryptoMaterial> buildRegistrationMaterial({
    required String password,
    required List<String> recoveryMnemonic,
  }) async {
    final sodium = await _sodiumLoader();

    final authSalt = sodium.randombytes.buf(CryptoParams.saltLength);
    final encSalt = sodium.randombytes.buf(CryptoParams.saltLength);
    final recoverySalt = sodium.randombytes.buf(CryptoParams.saltLength);

    final authKey = _deriveKey(sodium, password, authSalt);
    final masterKey = _deriveKey(sodium, password, encSalt);
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

            return RegistrationCryptoMaterial(
              authHash: base64.encode(authKey.extractBytes()),
              authSalt: authSalt,
              encSalt: encSalt,
              recoverySalt: recoverySalt,
              publicKey: Uint8List.fromList(keyPair.publicKey),
              encryptedPrivateKey: encryptedPrivateKey,
              encryptedPrivateKeyByRecovery: encryptedPrivateKeyByRecovery,
              masterKey: masterKey.extractBytes(),
              privateKey: Uint8List.fromList(privateKeyBytes),
            );
          } finally {
            privateKeyBytes.fillRange(0, privateKeyBytes.length, 0);
          }
        } finally {
          keyPair.dispose();
        }
      } finally {
        recoveryKey.dispose();
      }
    } finally {
      authKey.dispose();
      masterKey.dispose();
    }
  }

  /// Re-derives the auth credential and master key for a master-password
  /// change (CVT-273) and re-wraps the private key under the new master
  /// key.
  ///
  /// [currentPassword] unwraps the existing private key (its MAC check is
  /// the proof the user knows the old password — a wrong password throws
  /// [ChangePasswordWrongCurrentException]). [newPassword] then drives a
  /// fresh `authHash` (new [ChangePasswordMaterial.authSalt]) and a fresh
  /// `MK` (new [ChangePasswordMaterial.encSalt]) under which the private
  /// key is re-wrapped. The recovery mnemonic is intentionally left
  /// untouched — only the password-derived material rotates.
  ///
  /// Retains the new raw `MK` and the private key on the result so the
  /// live session can keep the vault unlocked with the new password.
  Future<ChangePasswordMaterial> buildChangePasswordMaterial({
    required String currentPassword,
    required String newPassword,
    required String currentEncSaltBase64,
    required String currentEncryptedPrivateKeyBase64,
  }) async {
    final sodium = await _sodiumLoader();
    final currentEncSalt = base64.decode(currentEncSaltBase64);

    final currentMasterKey = _deriveKey(sodium, currentPassword, currentEncSalt);
    Uint8List? privateKeyBytes;
    try {
      privateKeyBytes = _openPrivateKey(
        sodium,
        currentMasterKey,
        currentEncryptedPrivateKeyBase64,
      );

      final newAuthSalt = sodium.randombytes.buf(CryptoParams.saltLength);
      final newEncSalt = sodium.randombytes.buf(CryptoParams.saltLength);
      final newAuthKey = _deriveKey(sodium, newPassword, newAuthSalt);
      final newMasterKey = _deriveKey(sodium, newPassword, newEncSalt);
      try {
        final newEncryptedPrivateKey = _encryptWithKey(
          sodium,
          plaintext: privateKeyBytes,
          key: newMasterKey,
        );
        return ChangePasswordMaterial(
          authHash: base64.encode(newAuthKey.extractBytes()),
          authSalt: newAuthSalt,
          encSalt: newEncSalt,
          encryptedPrivateKey: newEncryptedPrivateKey,
          masterKey: newMasterKey.extractBytes(),
          privateKey: Uint8List.fromList(privateKeyBytes),
        );
      } finally {
        newAuthKey.dispose();
        newMasterKey.dispose();
      }
    } finally {
      if (privateKeyBytes != null) {
        privateKeyBytes.fillRange(0, privateKeyBytes.length, 0);
      }
      currentMasterKey.dispose();
    }
  }

  /// Splits the base64 blob into `nonce || ciphertext` and opens it with
  /// [key]. Throws [ChangePasswordWrongCurrentException] on any MAC
  /// failure (constant-time — callers cannot distinguish wrong password
  /// from tampered ciphertext).
  Uint8List _openPrivateKey(
    SodiumSumo sodium,
    SecureKey key,
    String encryptedBase64,
  ) {
    final combined = base64.decode(encryptedBase64);
    final nonceBytes = sodium.crypto.secretBox.nonceBytes;
    if (combined.length <= nonceBytes) {
      throw const ChangePasswordWrongCurrentException();
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
      throw const ChangePasswordWrongCurrentException();
    }
  }

  /// Runs `crypto_pwhash` (Argon2id) with the project-wide cost
  /// parameters and returns a [SecureKey] backed by locked memory.
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
  /// `nonce || ciphertext` blob, matching the format used by onboarding,
  /// unlock, recovery, and the web panel.
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

/// Crypto material produced by [PasswordAuthCryptoService.buildRegistrationMaterial].
///
/// The wire fields ([authHash] + all `Uint8List` blobs) go into the
/// registration request; [masterKey] and [privateKey] are the retained
/// raw keys handed to the auth layer to seed the unlocked session. The
/// caller owns [masterKey] / [privateKey] and must zero them if it does
/// not hand them off.
class RegistrationCryptoMaterial {
  const RegistrationCryptoMaterial({
    required this.authHash,
    required this.authSalt,
    required this.encSalt,
    required this.recoverySalt,
    required this.publicKey,
    required this.encryptedPrivateKey,
    required this.encryptedPrivateKeyByRecovery,
    required this.masterKey,
    required this.privateKey,
  });

  /// Base64 Argon2id auth hash (from `password + authSalt`).
  final String authHash;

  /// 16-byte salt used to derive [authHash] — the server stores it and
  /// returns it from the login pre-check so the client can re-derive.
  final Uint8List authSalt;

  /// 16-byte salt used to derive the master key (`password + encSalt`).
  /// Persisted as the account `salt` and returned by `GET /api/account`.
  final Uint8List encSalt;

  /// 16-byte salt for the recovery-mnemonic key derivation.
  final Uint8List recoverySalt;

  /// 32-byte X25519 public key.
  final Uint8List publicKey;

  /// Private key wrapped under the master key (`nonce || ciphertext`).
  final Uint8List encryptedPrivateKey;

  /// Private key wrapped under the recovery key (`nonce || ciphertext`).
  final Uint8List encryptedPrivateKeyByRecovery;

  /// Retained raw 32-byte master key — in memory only.
  final Uint8List masterKey;

  /// Retained raw 32-byte X25519 private key — in memory only.
  final Uint8List privateKey;
}

/// Crypto material produced by [PasswordAuthCryptoService.buildChangePasswordMaterial].
class ChangePasswordMaterial {
  const ChangePasswordMaterial({
    required this.authHash,
    required this.authSalt,
    required this.encSalt,
    required this.encryptedPrivateKey,
    required this.masterKey,
    required this.privateKey,
  });

  /// Base64 Argon2id auth hash derived from the new password.
  final String authHash;

  /// New 16-byte auth salt.
  final Uint8List authSalt;

  /// New 16-byte master-key salt (persisted as the account `salt`).
  final Uint8List encSalt;

  /// Private key re-wrapped under the new master key.
  final Uint8List encryptedPrivateKey;

  /// Retained raw new master key — in memory only.
  final Uint8List masterKey;

  /// Retained raw private key — in memory only.
  final Uint8List privateKey;
}

/// Thrown when the current master password supplied to the change-password
/// flow fails to decrypt the existing private-key ciphertext (i.e. the
/// user typed the wrong current password).
class ChangePasswordWrongCurrentException implements Exception {
  const ChangePasswordWrongCurrentException();

  @override
  String toString() => 'ChangePasswordWrongCurrentException';
}
