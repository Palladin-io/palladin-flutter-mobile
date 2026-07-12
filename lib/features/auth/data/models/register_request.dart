import 'dart:convert';
import 'dart:typed_data';

/// DTO sent to `POST /api/auth/register`.
///
/// Carries the account identity ([email], [displayName], [preferredLanguage])
/// alongside the full zero-knowledge crypto bundle. All binary fields are
/// base64-encoded strings on the wire — the backend's FastEndpoints binder
/// deserializes them into `byte[]`.
///
/// [authHash] is the client's Argon2id output for authentication; the
/// server re-hashes it at rest. It is derived from a **separate** salt
/// ([authSalt]) than the master key, so it reveals nothing about the
/// master key.
class RegisterRequest {
  const RegisterRequest({
    required this.email,
    required this.displayName,
    required this.preferredLanguage,
    required this.authHash,
    required this.authSalt,
    required this.salt,
    required this.recoverySalt,
    required this.publicKey,
    required this.encryptedPrivateKey,
    required this.encryptedPrivateKeyByRecovery,
  });

  final String email;
  final String displayName;

  /// `"pl"` / `"en"` — used by the backend to localize the verification
  /// email template.
  final String preferredLanguage;

  /// Base64 Argon2id auth hash (from `password + authSalt`).
  final String authHash;

  /// 16-byte auth salt (client-generated, stored server-side, returned by
  /// the login pre-check).
  final Uint8List authSalt;

  /// 16-byte master-key salt (persisted as the account `salt`).
  final Uint8List salt;

  /// 16-byte recovery-mnemonic salt.
  final Uint8List recoverySalt;

  /// 32-byte X25519 public key.
  final Uint8List publicKey;

  /// Private key wrapped under the master key (`nonce || ciphertext`).
  final Uint8List encryptedPrivateKey;

  /// Private key wrapped under the recovery key (`nonce || ciphertext`).
  final Uint8List encryptedPrivateKeyByRecovery;

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'displayName': displayName,
      'preferredLanguage': preferredLanguage,
      'authHash': authHash,
      'authSalt': base64Encode(authSalt),
      'salt': base64Encode(salt),
      'recoverySalt': base64Encode(recoverySalt),
      'publicKey': base64Encode(publicKey),
      'encryptedPrivateKey': base64Encode(encryptedPrivateKey),
      'encryptedPrivateKeyByRecovery': base64Encode(encryptedPrivateKeyByRecovery),
    };
  }
}
