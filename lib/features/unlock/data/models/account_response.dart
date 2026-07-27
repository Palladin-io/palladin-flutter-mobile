/// DTO returned by `GET /api/account`.
///
/// Contains the persisted salt and the private-key ciphertext encrypted
/// with the master key. Both are transported as base64-encoded strings;
/// the backend's FastEndpoints binder serializes `byte[]` as base64.
///
/// [recoverySalt] and [encryptedPrivateKeyByRecovery] are populated on
/// every onboarded account and consumed by the account-recovery flow to
/// unwrap the user's private key via the 24-word mnemonic.
class AccountResponse {
  const AccountResponse({
    this.userId,
    this.memberKeyVersion,
    required this.salt,
    required this.encryptedPrivateKey,
    this.recoverySalt,
    this.encryptedPrivateKeyByRecovery,
  });

  /// Member recipient identifier used in Vault-key wrapper scope.
  final String? userId;

  /// Current X25519 member recipient-key version.
  final int? memberKeyVersion;

  /// 16-byte Argon2id salt for the master-password derivation.
  final String salt;

  /// Base64-encoded `nonce || ciphertext` blob — private key encrypted
  /// with the master key via `crypto_secretbox_easy`.
  final String encryptedPrivateKey;

  /// 16-byte Argon2id salt for the recovery-mnemonic derivation.
  ///
  /// Nullable because older accounts (pre-recovery migration) may not
  /// have persisted recovery material yet.
  final String? recoverySalt;

  /// Base64-encoded `nonce || ciphertext` blob — private key encrypted
  /// with the recovery key derived from the 24-word mnemonic.
  ///
  /// Nullable for the same reason as [recoverySalt].
  final String? encryptedPrivateKeyByRecovery;

  factory AccountResponse.fromJson(Map<String, dynamic> json) {
    return AccountResponse(
      userId: json['userId'] as String?,
      memberKeyVersion: json['memberKeyVersion'] as int?,
      salt: json['salt'] as String,
      encryptedPrivateKey: json['encryptedPrivateKey'] as String,
      recoverySalt: json['recoverySalt'] as String?,
      encryptedPrivateKeyByRecovery:
          json['encryptedPrivateKeyByRecovery'] as String?,
    );
  }
}
