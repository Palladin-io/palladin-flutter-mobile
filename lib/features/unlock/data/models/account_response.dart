/// DTO returned by `GET /api/account`.
///
/// Contains the persisted salt and the private-key ciphertext encrypted
/// with the master key. Both are transported as base64-encoded strings;
/// the backend's FastEndpoints binder serializes `byte[]` as base64.
class AccountResponse {
  const AccountResponse({
    required this.salt,
    required this.encryptedPrivateKey,
  });

  /// 16-byte Argon2id salt for the master-password derivation.
  final String salt;

  /// Base64-encoded `nonce || ciphertext` blob — private key encrypted
  /// with the master key via `crypto_secretbox_easy`.
  final String encryptedPrivateKey;

  factory AccountResponse.fromJson(Map<String, dynamic> json) {
    return AccountResponse(
      salt: json['salt'] as String,
      encryptedPrivateKey: json['encryptedPrivateKey'] as String,
    );
  }
}
