import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/config/env_config.dart';
import 'package:mobile_palladin/core/network/api_client.dart';
import 'package:mobile_palladin/core/storage/secure_token_storage.dart';

void main() {
  group('createDio', () {
    test('configures Dio with correct baseUrl', () {
      FlutterSecureStorage.setMockInitialValues({});
      final config = EnvConfig.staging();
      final storage = SecureTokenStorage(const FlutterSecureStorage());
      final dio = createDio(config, storage);

      expect(dio.options.baseUrl, config.apiBaseUrl);
    });

    test('attaches interceptors including analytics headers', () {
      FlutterSecureStorage.setMockInitialValues({});
      final config = EnvConfig.staging();
      final storage = SecureTokenStorage(const FlutterSecureStorage());
      final dio = createDio(config, storage);

      expect(dio.interceptors.length, greaterThanOrEqualTo(2));
    });
  });
}
