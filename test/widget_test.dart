import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_claw_vault/config/env_config.dart';

void main() {
  test('EnvConfig staging has correct values', () {
    final config = EnvConfig.staging();
    expect(config.flavor, AppFlavor.staging);
    expect(config.appName, 'Claw Vault (Stage)');
    expect(config.apiBaseUrl, 'https://api.stage.clawvault.io');
    expect(config.isStaging, isTrue);
    expect(config.isProduction, isFalse);
  });

  test('EnvConfig production has correct values', () {
    final config = EnvConfig.production();
    expect(config.flavor, AppFlavor.production);
    expect(config.appName, 'Claw Vault');
    expect(config.apiBaseUrl, 'https://api.clawvault.io');
    expect(config.isStaging, isFalse);
    expect(config.isProduction, isTrue);
  });
}
