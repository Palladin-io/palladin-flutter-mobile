import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/onboarding/data/models/account_setup_request.dart';

void main() {
  test(
    'serializes the password auth credential in the canonical setup body',
    () {
      final authCredential = Uint8List.fromList(
        List<int>.generate(32, (i) => i),
      );
      final request = AccountSetupRequest(
        securityVersion: 1,
        kdfProfileId: 'argon2id-v1',
        newAuthCredential: authCredential,
        salt: Uint8List(16),
        recoverySalt: Uint8List(16),
        publicKey: Uint8List(32),
        encryptedPrivateKey: Uint8List(48),
        encryptedPrivateKeyByRecovery: Uint8List(48),
      ).toJson();

      expect(request.keys, contains('newAuthCredential'));
      expect(
        base64Url.decode(
          base64Url.normalize(request['newAuthCredential'] as String),
        ),
        authCredential,
      );
      expect(request, isNot(contains('authCredential')));
    },
  );
}
