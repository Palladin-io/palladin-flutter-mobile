import 'dart:convert';
import 'dart:typed_data';

/// DTO sent to `POST /api/account/setup` to complete the zero-knowledge
/// onboarding flow.
///
/// All fields are transported as base64-encoded strings — the backend's
/// FastEndpoints binder deserializes base64 JSON strings into `byte[]`.
class AccountSetupRequest {
  const AccountSetupRequest({
    required this.securityVersion,
    required this.kdfProfileId,
    required this.newAuthCredential,
    required this.salt,
    required this.recoverySalt,
    required this.publicKey,
    required this.encryptedPrivateKey,
    required this.encryptedPrivateKeyByRecovery,
  });

  final int securityVersion;
  final String kdfProfileId;
  final Uint8List newAuthCredential;

  /// 16-byte Argon2id salt for the master-password key derivation.
  final Uint8List salt;

  /// 16-byte Argon2id salt for the recovery-key derivation (from mnemonic).
  final Uint8List recoverySalt;

  /// 32-byte X25519 public key.
  final Uint8List publicKey;

  /// Private key encrypted with the master key (nonce-prepended
  /// `crypto_secretbox_easy` ciphertext).
  final Uint8List encryptedPrivateKey;

  /// Private key encrypted with the recovery key (nonce-prepended
  /// `crypto_secretbox_easy` ciphertext).
  final Uint8List encryptedPrivateKeyByRecovery;

  Map<String, dynamic> toJson() {
    return {
      'securityVersion': securityVersion,
      'kdfProfileId': kdfProfileId,
      'newAuthCredential': _encode(newAuthCredential),
      'kdfSalt': _encode(salt),
      'recoverySalt': _encode(recoverySalt),
      'publicKey': _encode(publicKey),
      'encryptedPrivateKey': _encode(encryptedPrivateKey),
      'encryptedPrivateKeyByRecovery': _encode(encryptedPrivateKeyByRecovery),
    };
  }

  String _encode(Uint8List value) => base64UrlEncode(value).replaceAll('=', '');
}
