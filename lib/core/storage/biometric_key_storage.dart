import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/app_logger.dart';

/// Shared constants and the logout cleanup helper for the biometric master
/// key.
///
/// The MK itself now lives in an enclave-bound, biometric-gated store (see
/// [BiometricStorageKeyStore]); this class only owns:
///  - the plaintext enrollment marker (non-secret) used for a cheap,
///    non-prompting "is biometric unlock set up?" check, and
///  - the [clear] helper called from `AuthRepositoryImpl.logout()`.
///
/// [legacyRawKey] is the pre-hardening key under which the *raw* MK used to be
/// written directly to `flutter_secure_storage`. It is deleted on every clear
/// (and on every enroll) so an upgrading install can never keep a
/// non-enclave-bound MK sitting on disk.
abstract final class BiometricKeyStorage {
  /// Pre-hardening key: raw MK persisted directly to secure storage.
  /// Retained ONLY so we can proactively delete it on upgrade.
  static const legacyRawKey = 'vault_mk';

  /// Non-secret marker: `'1'` once the MK has been enrolled into the
  /// enclave-bound biometric store.
  static const enrolledMarkerKey = 'vault_mk_enrolled';

  static const iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.unlocked_this_device,
    synchronizable: false,
  );

  static const androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
  );

  /// Clears the enrollment marker AND proactively deletes any legacy raw MK.
  ///
  /// Best-effort — never throws, never prompts (touches only
  /// `flutter_secure_storage`, not the enclave-protected key). The orphaned
  /// enclave blob, if any, is harmless: it is biometric-gated and gets
  /// overwritten on the next enroll. Called on logout.
  static Future<void> clear(FlutterSecureStorage storage) async {
    for (final key in const [legacyRawKey, enrolledMarkerKey]) {
      try {
        await storage.delete(
          key: key,
          iOptions: iosOptions,
          aOptions: androidOptions,
        );
      } catch (e) {
        AppLogger.w('BiometricKey', 'Failed to clear $key: ${e.runtimeType}');
      }
    }
  }
}
