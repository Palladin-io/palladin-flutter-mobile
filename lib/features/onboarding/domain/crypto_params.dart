/// Argon2id KDF parameters used across the zero-knowledge flow.
///
/// Values match the web panel and zero-knowledge spec so that a vault
/// set up on any platform can be unlocked from any other:
///   m = 19456 KiB (~19 MB), t = 2 iterations, p = 1 lane, 32-byte output.
///
/// `memLimit` is exposed in **bytes** because libsodium's
/// `crypto_pwhash` takes `memlimit` in bytes, while the spec expresses
/// the cost in KiB.
abstract final class CryptoParams {
  /// Argon2id memory cost in KiB, matching the public spec value (`m = 19456`).
  static const int argon2MemoryKiB = 19456;

  /// Argon2id memory cost in bytes — the unit expected by libsodium.
  static const int argon2MemLimit = argon2MemoryKiB * 1024;

  /// Argon2id time cost / iteration count (`t = 2`).
  static const int argon2OpsLimit = 2;

  /// Derived key length in bytes (32 = 256 bits).
  static const int derivedKeyLength = 32;

  /// Salt length in bytes for Argon2id — must equal
  /// `crypto_pwhash_SALTBYTES` (16).
  static const int saltLength = 16;

  /// Number of BIP-39 words used for the recovery key mnemonic.
  ///
  /// 24 words ≈ 256 bits of entropy.
  static const int recoveryMnemonicWordCount = 24;

  /// Recovery-mnemonic entropy in bytes (256 bits).
  static const int recoveryEntropyBytes = 32;

  /// Number of recovery-mnemonic words the user must confirm after
  /// backing up the recovery key.
  static const int recoveryConfirmationWordCount = 3;
}
