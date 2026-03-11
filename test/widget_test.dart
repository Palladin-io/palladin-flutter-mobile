import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_claw_vault/app.dart';
import 'package:mobile_claw_vault/config/env_config.dart';

void main() {
  testWidgets('App displays environment name', (WidgetTester tester) async {
    final config = EnvConfig.staging();
    await tester.pumpWidget(ClawVaultApp(config: config));

    expect(find.text('Environment: staging'), findsOneWidget);
    expect(find.text('API: https://api.stage.clawvault.io'), findsOneWidget);
  });

  testWidgets('App displays production config when given production flavor',
      (WidgetTester tester) async {
    final config = EnvConfig.production();
    await tester.pumpWidget(ClawVaultApp(config: config));

    expect(find.text('Environment: production'), findsOneWidget);
    expect(find.text('API: https://api.clawvault.io'), findsOneWidget);
  });

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
