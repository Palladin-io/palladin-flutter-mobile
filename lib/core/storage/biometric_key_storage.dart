import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/app_logger.dart';

/// Shared constants and helpers for the persisted biometric master key.
///
/// Both [UnlockCubit] (write/read) and [AuthRepositoryImpl] (clear on logout)
/// reference this class so key name and storage options stay in one place.
abstract final class BiometricKeyStorage {
  static const storageKey = 'vault_mk';

  static const iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.unlocked_this_device,
    synchronizable: false,
  );

  static const androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
  );

  /// Deletes the stored MK from the OS keychain/keystore. Best-effort — never throws.
  static Future<void> clear(FlutterSecureStorage storage) async {
    try {
      await storage.delete(
        key: storageKey,
        iOptions: iosOptions,
        aOptions: androidOptions,
      );
    } catch (e) {
      AppLogger.w('BiometricKey', 'Failed to clear key: ${e.runtimeType}');
    }
  }
}
