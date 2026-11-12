import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/config/env_config.dart';
import 'package:mobile_palladin/core/crypto/biometric_profile_binding.dart';

void main() {
  String bind({
    AppFlavor flavor = AppFlavor.production,
    String api = 'https://api.example.test',
    String principal = 'principal',
  }) => biometricProfileBinding(
    flavor: flavor,
    apiBaseUrl: api,
    principalId: principal,
  );

  test('account binding is stable for equivalent configured API roots', () {
    expect(bind(api: 'https://API.EXAMPLE.TEST:443/'), bind());
    expect(
      bind(),
      '9cc57a8265db6cb3c992ef56ead682f1f997556aa5dbc5ea7a4c92b5de593946',
    );
  });

  test('account, API and flavor each separate protected unlock material', () {
    expect(bind(principal: 'other'), isNot(bind()));
    expect(bind(api: 'https://other.example.test'), isNot(bind()));
    expect(bind(flavor: AppFlavor.staging), isNot(bind()));
    expect(bind(api: 'https://api.example.test/tenant'), isNot(bind()));
  });

  test('ambiguous remote configuration cannot bind protected material', () {
    for (final api in [
      'http://api.example.test',
      'https://user@api.example.test',
      'https://api.example.test?tenant=other',
      'https://api.example.test#other',
    ]) {
      expect(() => bind(api: api), throwsFormatException);
    }
    expect(() => bind(principal: ''), throwsFormatException);
  });
}
