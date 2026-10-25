import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/app_logger.dart';
import 'biometric_key_store.dart';

/// Marker constants + logout cleanup for the biometric master key. The MK
/// itself lives in the OS-protected store ([BiometricStorageKeyStore]); this
/// class only owns the non-secret enrollment marker and the legacy-key purge.
abstract final class BiometricKeyStorage {
  /// Pre-hardening key: raw MK once persisted directly to secure storage.
  /// Retained only so we can proactively delete it on upgrade.
  static const legacyRawKey = 'vault_mk';

  /// Non-secret marker: `'1'` once the MK has been enrolled.
  static const enrolledMarkerKey = 'vault_mk_enrolled';

  static const iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.unlocked_this_device,
    synchronizable: false,
  );

  static const androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
  );

  /// Attempts both deletions and reports failure without reading key values.
  static Future<void> clear(FlutterSecureStorage storage) async {
    var failed = false;
    for (final key in const [legacyRawKey, enrolledMarkerKey]) {
      try {
        await storage.delete(
          key: key,
          iOptions: iosOptions,
          aOptions: androidOptions,
        );
      } catch (e) {
        failed = true;
        AppLogger.w('BiometricKey', 'Failed to clear $key: ${e.runtimeType}');
      }
    }
    if (failed) throw const BiometricKeyCleanupException();
  }
}
