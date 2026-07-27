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
    required this.baseCredentialRevision,
    required this.basePrivateKeyWrapRevision,
    required this.newKdfSalt,
    this.newAuthCredential,
    required this.newEncryptedPrivateKey,
    required this.newRecoverySalt,
    required this.newEncryptedPrivateKeyByRecovery,
  });

  /// 16-byte Argon2id salt for the new master-password key derivation.
  final int baseCredentialRevision;
  final int basePrivateKeyWrapRevision;
  final Uint8List newKdfSalt;
  final Uint8List? newAuthCredential;

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
      'securityVersion': 1,
      'kdfProfileId': 'identity-argon2id-password-v1',
      'baseCredentialRevision': baseCredentialRevision,
      'basePrivateKeyWrapRevision': basePrivateKeyWrapRevision,
      'newKdfSalt': _encode(newKdfSalt),
      if (newAuthCredential case final value?)
        'newAuthCredential': _encode(value),
      'newEncryptedPrivateKey': _encode(newEncryptedPrivateKey),
      'newRecoverySalt': _encode(newRecoverySalt),
      'newEncryptedPrivateKeyByRecovery': _encode(
        newEncryptedPrivateKeyByRecovery,
      ),
    };
  }

  String _encode(Uint8List value) => base64UrlEncode(value).replaceAll('=', '');
}
