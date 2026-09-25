import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_palladin/config/env_config.dart';

void main() {
  test('local configuration does not need cloud build inputs', () {
    final config = EnvConfig.local();
    expect(config.isLocal, isTrue);
    expect(Uri.parse(config.apiBaseUrl).host, anyOf('localhost', '10.0.2.2'));
  });

  for (final invalid in [
    '',
    'http://api.example.test',
    'api.example.test',
    'https://user:password@api.example.test',
    'https://api.example.test?token=example',
    'https://api.example.test#fragment',
    ' https://api.example.test',
  ]) {
    test('cloud configurations reject invalid API input: $invalid', () {
      expect(() => EnvConfig.staging(apiBaseUrl: invalid), throwsStateError);
      expect(() => EnvConfig.production(apiBaseUrl: invalid), throwsStateError);
    });
  }

  test('cloud configurations have no implicit destination', () {
    expect(() => EnvConfig.staging(), throwsStateError);
    expect(() => EnvConfig.production(), throwsStateError);
    expect(
      () => EnvConfig.production(useStagingBackend: true),
      throwsStateError,
    );
  });

  test('explicit self-hosted HTTPS base path is preserved', () {
    final config = EnvConfig.staging(
      apiBaseUrl: 'https://vault.example/tenant/',
    );
    expect(config.apiBaseUrl, 'https://vault.example/tenant/');
  });

  test('EnvConfig staging has correct values', () {
    final config = EnvConfig.staging(apiBaseUrl: 'https://stage.example.test');
    expect(config.flavor, AppFlavor.staging);
    expect(config.appName, 'Palladin (Stage)');
    expect(config.apiBaseUrl, 'https://stage.example.test');
    expect(config.isStaging, isTrue);
    expect(config.isProduction, isFalse);
  });

  test('EnvConfig production has correct values', () {
    final config = EnvConfig.production(apiBaseUrl: 'https://api.example.test');
    expect(config.flavor, AppFlavor.production);
    expect(config.appName, 'Palladin');
    expect(config.apiBaseUrl, 'https://api.example.test');
    expect(config.isStaging, isFalse);
    expect(config.isProduction, isTrue);
  });

  test(
    'EnvConfig store testing keeps production identity with staging API',
    () {
      final config = EnvConfig.production(
        useStagingBackend: true,
        apiBaseUrl: 'https://stage.example.test',
      );
      expect(config.flavor, AppFlavor.production);
      expect(config.appName, 'Palladin');
      expect(config.apiBaseUrl, 'https://stage.example.test');
      expect(config.isStaging, isFalse);
      expect(config.isProduction, isTrue);
    },
  );
}
