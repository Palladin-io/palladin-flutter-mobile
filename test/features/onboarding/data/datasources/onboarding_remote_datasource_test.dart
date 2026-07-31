import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/onboarding/data/datasources/onboarding_remote_datasource.dart';
import 'package:mobile_palladin/features/onboarding/data/models/account_setup_request.dart';

void main() {
  test(
    'uses canonical setup, challenge and default-Vault HTTP contracts',
    () async {
      final calls = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              calls.add(options);
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: options.path == '/api/account/setup' ? 204 : 200,
                  data: options.path == '/api/vaults/creation-challenges'
                      ? {'vaultId': '33333333-3333-4333-8333-333333333333'}
                      : const {},
                ),
              );
            },
          ),
        );
      final remote = OnboardingRemoteDatasource(dio);

      await remote.setupAccount(
        AccountSetupRequest(
          securityVersion: 1,
          kdfProfileId: 'argon2id-v1',
          newAuthCredential: Uint8List(32),
          salt: Uint8List(16),
          recoverySalt: Uint8List(16),
          publicKey: Uint8List(32),
          encryptedPrivateKey: Uint8List(48),
          encryptedPrivateKeyByRecovery: Uint8List(48),
        ),
      );
      final challenge = await remote.issueVaultCreationChallenge();
      await remote.createDefaultVault({
        'vaultId': challenge['vaultId'],
        'memberVaultMetadata': <String, dynamic>{},
      });

      expect(calls.map((call) => call.path), [
        '/api/account/setup',
        '/api/vaults/creation-challenges',
        '/api/account/default-vault',
      ]);
      expect(calls.every((call) => call.method == 'POST'), isTrue);
      final setup = calls[0].data as Map<String, dynamic>;
      expect(setup['newAuthCredential'], isA<String>());
      final create = calls[2].data as Map<String, dynamic>;
      expect(create['vaultId'], challenge['vaultId']);
      expect(create, isNot(contains('wrappedVK')));
    },
  );
}
