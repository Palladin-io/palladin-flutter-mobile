import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Android-contract simulator for the pinned native plugin. Flutter host tests
// select macOS/Linux options via dart:io, so exercise Android options explicitly.
class AndroidContractStorage extends FlutterSecureStorage {
  AndroidContractStorage(AndroidOptions options) : super(aOptions: options);
  final legacy = <String, String>{};
  final encrypted = <String, String>{};
  Map<String, String> data(AndroidOptions? options) {
    if ((options ?? aOptions).toMap()['encryptedSharedPreferences'] == 'true') {
      encrypted.addAll(legacy);
      legacy.clear();
      return encrypted;
    }
    return legacy;
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => data(aOptions)[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) data(aOptions)[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    data(aOptions).remove(key);
  }
}
