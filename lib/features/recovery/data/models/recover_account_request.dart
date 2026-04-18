import 'dart:convert';
import 'dart:typed_data';

/// DTO sent to `PUT /api/account/recovery` to complete the account
/// recovery flow.
///
/// All fields are transported as base64-encoded strings — the backend's
/// FastEndpoints binder deserializes base64 JSON strings into `byte[]`.
/// Field layout matches the web panel's `RecoverAccountPayload`.
class RecoverAccountRequest {
  const RecoverAccountRequest({
    required this.newSalt,
    required this.newEncryptedPrivateKey,
    required this.newRecoverySalt,
    required this.newEncryptedPrivateKeyByRecovery,
  });

  /// 16-byte Argon2id salt for the new master-password key derivation.
  final Uint8List newSalt;

  /// Private key encrypted with the freshly-derived master key
  /// (`nonce || ciphertext` from `crypto_secretbox_easy`).
  final Uint8List newEncryptedPrivateKey;

  /// 16-byte Argon2id salt for the new recovery-mnemonic derivation.
  final Uint8List newRecoverySalt;

  /// Private key encrypted with the freshly-derived recovery key
  /// (`nonce || ciphertext` from `crypto_secretbox_easy`).
  final Uint8List newEncryptedPrivateKeyByRecovery;

  Map<String, dynamic> toJson() {
    return {
      'newSalt': base64Encode(newSalt),
      'newEncryptedPrivateKey': base64Encode(newEncryptedPrivateKey),
      'newRecoverySalt': base64Encode(newRecoverySalt),
      'newEncryptedPrivateKeyByRecovery':
          base64Encode(newEncryptedPrivateKeyByRecovery),
    };
  }
}
