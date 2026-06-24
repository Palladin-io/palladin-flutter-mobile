import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_palladin/config/env_config.dart';

void main() {
  test('EnvConfig staging has correct values', () {
    final config = EnvConfig.staging();
    expect(config.flavor, AppFlavor.staging);
    expect(config.appName, 'Palladin (Stage)');
    expect(config.apiBaseUrl, 'https://api.stage.palladin.io');
    expect(config.isStaging, isTrue);
    expect(config.isProduction, isFalse);
  });

  test('EnvConfig production has correct values', () {
    final config = EnvConfig.production();
    expect(config.flavor, AppFlavor.production);
    expect(config.appName, 'Palladin');
    expect(config.apiBaseUrl, 'https://api.palladin.io');
    expect(config.isStaging, isFalse);
    expect(config.isProduction, isTrue);
  });
}
