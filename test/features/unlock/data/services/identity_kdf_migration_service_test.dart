import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/auth/data/datasources/password_auth_remote_datasource.dart';
import 'package:mobile_palladin/features/auth/data/services/password_auth_crypto_service.dart';
import 'package:mobile_palladin/features/unlock/data/datasources/account_remote_datasource.dart';
import 'package:mobile_palladin/features/unlock/data/models/account_response.dart';
import 'package:mobile_palladin/features/unlock/data/services/identity_kdf_migration_service.dart';
import 'package:mobile_palladin/features/unlock/data/services/identity_kdf_service.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;

String _encode(List<int> value) => base64Url.encode(value).replaceAll('=', '');

void main() {
  test(
    'migration retry reuses one CAS request and uploads no raw secrets',
    () async {
      final library = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
      final sodium = await sodium_ffi.SodiumSumoInit.init(
        () => DynamicLibrary.open(library ?? 'libsodium.so'),
      );
      Future<sodium_ffi.SodiumSumo> sodiumLoader() async => sodium;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
      final postedBodies = <Map<String, dynamic>>[];
      var migrationAttempts = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/api/auth/login/salt') {
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'accountId': '00112233-4455-6677-8899-aabbccddeeff',
                    'profileId': IdentityKdfProfile.legacyId,
                    'securityVersion': 1,
                    'kdfSalt': _encode(List<int>.generate(16, (i) => i)),
                    'memoryKiB': 19456,
                    'iterations': 2,
                    'parallelism': 1,
                    'accountSecretRequired': false,
                  },
                ),
              );
              return;
            }
            if (options.path == '/api/account/kdf/migrations') {
              postedBodies.add(Map<String, dynamic>.from(options.data as Map));
              migrationAttempts += 1;
              if (migrationAttempts == 1) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.connectionError,
                  ),
                );
              } else {
                handler.resolve(
                  Response<void>(requestOptions: options, statusCode: 204),
                );
              }
              return;
            }
            handler.reject(DioException(requestOptions: options));
          },
        ),
      );
      final service = IdentityKdfMigrationService(
        accountDatasource: AccountRemoteDatasource(dio),
        passwordDatasource: PasswordAuthRemoteDatasource(dio),
        legacyCrypto: PasswordAuthCryptoService(sodiumLoader: sodiumLoader),
        identityCrypto: IdentityKdfService(sodiumLoader: sodiumLoader),
        sodiumLoader: sodiumLoader,
      );
      final privateKey = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final pending = await service.prepare(
        password: 'correct horse battery staple',
        account: AccountResponse(
          userId: '00112233-4455-6677-8899-aabbccddeeff',
          email: 'member@example.com',
          salt: _encode(List<int>.filled(16, 9)),
          encryptedPrivateKey: 'unused',
          kdf: IdentityKdfMetadata(
            securityVersion: 1,
            minimumSecurityVersion: 1,
            profileId: IdentityKdfProfile.legacyId,
            kdfSalt: _encode(List<int>.filled(16, 9)),
            credentialRevision: 4,
            privateKeyWrapRevision: 7,
          ),
        ),
        legacyPrivateKey: privateKey,
      );
      final accountSecretSnapshot = Uint8List.fromList(pending.accountSecret);

      await expectLater(service.commit(), throwsA(isA<DioException>()));
      final result = await service.commit();

      expect(postedBodies, hasLength(2));
      expect(postedBodies[1], postedBodies[0]);
      for (final forbidden in const [
        'accountSecret',
        'accountRoot',
        'masterKey',
        'privateKey',
        'recoverySecret',
        'vk',
        'vdk',
      ]) {
        expect(postedBodies.first.containsKey(forbidden), isFalse);
      }
      expect(result.accountSecret, accountSecretSnapshot);
      expect(result.privateKey, privateKey);
      expect(pending.accountSecret, everyElement(0));
      result.accountSecret.fillRange(0, result.accountSecret.length, 0);
      result.masterKey.fillRange(0, result.masterKey.length, 0);
      result.privateKey.fillRange(0, result.privateKey.length, 0);
      accountSecretSnapshot.fillRange(0, accountSecretSnapshot.length, 0);
      privateKey.fillRange(0, privateKey.length, 0);
    },
  );
}
