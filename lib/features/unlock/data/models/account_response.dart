import '../services/identity_kdf_service.dart';

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
    required this.userId,
    this.email = '',
    required this.salt,
    required this.encryptedPrivateKey,
    this.kdf,
    this.memberKeyVersion,
    this.recoverySalt,
    this.encryptedPrivateKeyByRecovery,
  });

  /// Immutable RFC 4122 account identifier used by the v2 KDF framing.
  final String userId;
  final String email;

  /// 16-byte Argon2id salt for the master-password derivation.
  final String salt;

  /// Base64-encoded `nonce || ciphertext` blob — private key encrypted
  /// with the master key via `crypto_secretbox_easy`.
  final String encryptedPrivateKey;

  final IdentityKdfMetadata? kdf;
  final int? memberKeyVersion;

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
      userId: json['userId'] as String,
      email: json['email'] as String? ?? '',
      salt: json['salt'] as String,
      encryptedPrivateKey: json['encryptedPrivateKey'] as String,
      kdf: switch (json['kdf']) {
        final Map<String, dynamic> value => IdentityKdfMetadata.fromJson(value),
        _ => null,
      },
      memberKeyVersion: json['memberKeyVersion'] as int?,
      recoverySalt: json['recoverySalt'] as String?,
      encryptedPrivateKeyByRecovery:
          json['encryptedPrivateKeyByRecovery'] as String?,
    );
  }
}
