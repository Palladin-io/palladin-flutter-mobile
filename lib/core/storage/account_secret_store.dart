import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'device_secure_storage.dart';

/// Trusted-device copy of the Secret Key (`identity-kdf/v3`
/// `deviceAssistance.mobileHardwareWrapper`).
///
/// This is the protocol's explicit exception to the no-persistent-keys rule:
/// the Secret Key alone opens nothing without the master password. It does not
/// extend the separate biometric master-key persistence. iOS keeps it in a
/// this-device-only, non-synchronizable Keychain item; Android in
/// EncryptedSharedPreferences (Keystore AES-256-GCM), which the data
/// extraction rules exclude from backup and device transfer.
class AccountSecretStore {
  AccountSecretStore([FlutterSecureStorage storage = deviceSecureStorage])
    : _storage = storage;

  final FlutterSecureStorage _storage;

  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
  );

  static String itemKey(String accountId) =>
      'palladin.account-secret.${accountId.toLowerCase()}';

  Future<Uint8List?> read(String accountId) async {
    final value = await _storage.read(
      key: itemKey(accountId),
      iOptions: _iosOptions,
    );
    if (value == null) return null;
    try {
      final bytes = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(value)),
      );
      if (bytes.length == 32) return bytes;
      bytes.fillRange(0, bytes.length, 0);
    } on FormatException {
      // A corrupt item is treated as absent and replaced on next sign-in.
    }
    return null;
  }

  Future<void> write(String accountId, Uint8List accountSecret) {
    if (accountSecret.length != 32) {
      throw ArgumentError('Secret Key must be 32 bytes');
    }
    return _storage.write(
      key: itemKey(accountId),
      value: base64Url.encode(accountSecret).replaceAll('=', ''),
      iOptions: _iosOptions,
    );
  }

  /// Sign-out, forget-this-device, recovery and account deletion.
  Future<void> delete(String accountId) =>
      _storage.delete(key: itemKey(accountId), iOptions: _iosOptions);
}
