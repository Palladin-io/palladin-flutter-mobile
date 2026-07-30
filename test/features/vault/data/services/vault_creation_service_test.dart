import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/storage/secure_token_storage.dart';
import 'package:mobile_palladin/features/unlock/data/datasources/account_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_creation_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_crypto_service.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;

void main() {
  test(
    'creates only encrypted material and retries the identical atomic payload',
    () async {
      final library = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
      final sodium = await _loadSodium(library);
      if (sodium == null) {
        markTestSkipped('libsodium is unavailable on this test host');
        return;
      }
      const organizationId = '11111111-1111-4111-8111-111111111111';
      const userId = '22222222-2222-4222-8222-222222222222';
      const vaultId = '33333333-3333-4333-8333-333333333333';
      final jwtPayload = base64Url.encode(
        utf8.encode(jsonEncode({'org_id': organizationId})),
      );
      FlutterSecureStorage.setMockInitialValues({
        'access_token': 'header.$jwtPayload.signature',
      });
      final requests = <Map<String, dynamic>>[];
      var createAttempts = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              if (options.path == '/api/account') {
                handler.resolve(
                  Response<Map<String, dynamic>>(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'userId': userId,
                      'salt': '',
                      'encryptedPrivateKey': '',
                      'memberKeyVersion': 7,
                    },
                  ),
                );
                return;
              }
              if (options.path == '/api/vaults/creation-challenges') {
                handler.resolve(
                  Response<Map<String, dynamic>>(
                    requestOptions: options,
                    statusCode: 200,
                    data: {'vaultId': vaultId},
                  ),
                );
                return;
              }
              if (options.path == '/api/vaults') {
                requests.add(Map<String, dynamic>.from(options.data as Map));
                createAttempts++;
                if (createAttempts == 1 ||
                    createAttempts == 3 ||
                    createAttempts == 5) {
                  handler.reject(
                    DioException.connectionError(
                      requestOptions: options,
                      reason: 'simulated disconnect after request submission',
                    ),
                  );
                  return;
                }
                handler.resolve(
                  Response<Map<String, dynamic>>(
                    requestOptions: options,
                    statusCode: 201,
                    data: {
                      'id': vaultId,
                      'createdAt': '2026-07-26T12:00:00Z',
                      'updatedAt': '2026-07-26T12:00:00Z',
                    },
                  ),
                );
                return;
              }
              handler.next(options);
            },
          ),
        );
      final service = VaultCreationService(
        remote: VaultRemoteDatasource(dio),
        accountRemote: AccountRemoteDatasource(dio),
        tokenStorage: SecureTokenStorage(const FlutterSecureStorage()),
        crypto: VaultCryptoService(sodiumLoader: () async => sodium),
        sodiumLoader: () async => sodium,
      );
      final memberPrivateKey = Uint8List.fromList(
        List<int>.generate(32, (index) => index + 1),
      );

      Future<void> create() async {
        await service.create(
          name: 'Highly Secret Vault',
          description: 'Confidential description',
          icon: 'shield',
          color: '#123456',
          memberPrivateKey: memberPrivateKey,
        );
      }

      await expectLater(create(), throwsA(isA<DioException>()));
      final result = await service.create(
        name: 'Highly Secret Vault',
        description: 'Confidential description',
        icon: 'shield',
        color: '#123456',
        memberPrivateKey: memberPrivateKey,
      );

      expect(result.id, vaultId);
      expect(requests, hasLength(2));
      expect(requests[1], equals(requests[0]));
      final payload = requests.first;
      expect(payload['vaultId'], vaultId);
      expect(
        payload.keys,
        unorderedEquals({
          'vaultId',
          'memberVaultMetadata',
          'currentKeyEpoch',
          'creatorVaultKey',
          'discoveryKey',
          'vaultPrivateKeys',
          'vaultAgentMessagePublicKey',
          'vaultManifestSigningPublicKey',
        }),
      );
      expect(payload['vaultPrivateKeys'], hasLength(2));
      expect(payload['currentKeyEpoch'], {
        'vaultKeyVersion': 1,
        'vdkVersion': 1,
        'agentMessageKeyVersion': 1,
        'manifestSigningKeyVersion': 1,
      });
      final serialized = jsonEncode(payload);
      expect(serialized, isNot(contains('Highly Secret Vault')));
      expect(serialized, isNot(contains('Confidential description')));
      expect(serialized, isNot(contains('#123456')));
      expect(serialized, isNot(contains('shield')));

      await expectLater(create(), throwsA(isA<DioException>()));
      final changed = await service.create(
        name: 'Changed Vault',
        description: 'Different input',
        icon: 'key',
        color: '#654321',
        memberPrivateKey: memberPrivateKey,
      );
      expect(changed.name, 'Changed Vault');
      expect(requests, hasLength(4));
      expect(
        requests[3],
        isNot(equals(requests[2])),
        reason: 'changed input must not replay the previous pending payload',
      );

      await expectLater(create(), throwsA(isA<DioException>()));
      final changedMemberKey = Uint8List.fromList(
        List<int>.generate(32, (index) => index + 2),
      );
      await service.create(
        name: 'Highly Secret Vault',
        description: 'Confidential description',
        icon: 'shield',
        color: '#123456',
        memberPrivateKey: changedMemberKey,
      );
      expect(requests, hasLength(6));
      expect(
        requests[5],
        isNot(equals(requests[4])),
        reason: 'a changed Member key must rebuild the pending payload',
      );
    },
  );
}

Future<sodium_ffi.SodiumSumo?> _loadSodium(String? library) async {
  try {
    return await sodium_ffi.SodiumSumoInit.init(
      () => DynamicLibrary.open(library ?? 'libsodium.so'),
    );
  } on ArgumentError {
    return null;
  }
}
