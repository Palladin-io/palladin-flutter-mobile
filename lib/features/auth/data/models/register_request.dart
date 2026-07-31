import 'dart:convert';
import 'dart:typed_data';

import '../../../unlock/data/services/identity_kdf_service.dart';

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
    required this.accountId,
    required this.email,
    required this.displayName,
    required this.preferredLanguage,
    required this.authCredential,
    required this.kdfSalt,
    required this.recoverySalt,
    required this.publicKey,
    required this.encryptedPrivateKey,
    required this.encryptedPrivateKeyByRecovery,
  });

  final String accountId;

  final String email;
  final String displayName;

  /// `"pl"` / `"en"` — used by the backend to localize the verification
  /// email template.
  final String preferredLanguage;

  /// Base64 Argon2id auth hash (from `password + authSalt`).
  final String authCredential;

  /// 16-byte auth salt (client-generated, stored server-side, returned by
  /// the login pre-check).
  final Uint8List kdfSalt;

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
      'accountId': accountId,
      'email': email,
      'displayName': displayName,
      'preferredLanguage': preferredLanguage,
      'securityVersion': IdentityKdfProfile.securityVersion,
      'kdfProfileId': IdentityKdfProfile.id,
      'authCredential': authCredential,
      'kdfSalt': _encodeBytes(kdfSalt),
      'recoverySalt': _encodeBytes(recoverySalt),
      'publicKey': _encodeBytes(publicKey),
      'encryptedPrivateKey': _encodeBytes(encryptedPrivateKey),
      'encryptedPrivateKeyByRecovery': _encodeBytes(
        encryptedPrivateKeyByRecovery,
      ),
    };
  }

  String _encodeBytes(Uint8List value) =>
      base64UrlEncode(value).replaceAll('=', '');
}
