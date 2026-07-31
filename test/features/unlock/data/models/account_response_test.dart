import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/unlock/data/models/account_response.dart';

void main() {
  test('accepts the canonical pre-setup account response', () {
    final account = AccountResponse.fromJson(const {
      'userId': '00112233-4455-6677-8899-aabbccddeeff',
      'email': 'user@example.test',
      'salt': null,
      'encryptedPrivateKey': null,
      'kdf': null,
      'recoverySalt': null,
      'encryptedPrivateKeyByRecovery': null,
      'memberKeyVersion': null,
    });

    expect(account.salt, isNull);
    expect(account.encryptedPrivateKey, isNull);
    expect(account.kdf, isNull);
  });
}
