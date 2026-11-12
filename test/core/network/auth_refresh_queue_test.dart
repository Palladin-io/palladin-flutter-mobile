import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:mobile_palladin/config/env_config.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_request_controller.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_source_access_service.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_source_configuration_loader.dart';
import 'package:mobile_palladin/features/unlock/data/datasources/account_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_session_authority_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/network/auth_interceptor.dart';
import 'package:mobile_palladin/core/storage/secure_token_storage.dart';

class _Binding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _Binding();
  for (final scenario in [
    'refresh',
    'replacement',
    'replacement-after-retry',
    'biometric',
  ]) {
    test('queued old-token 401s: $scenario', () async {
      final replace = scenario.startsWith('replacement');
      final replaceAfterRetry = scenario == 'replacement-after-retry';
      final biometric = scenario == 'biometric';
      String token(String revision) =>
          'synthetic.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'same-user', 'org_id': 'org', 'authz_ver': '1', 'org_offline_policy': 1, 'org_offline_policy_ver': 1, 'jti': revision})))}.synthetic';
      FlutterSecureStorage.setMockInitialValues({});
      final storage = SecureTokenStorage(const FlutterSecureStorage());
      Future<void> login(String revision) => storage.saveTokens(
        accessToken: token(revision),
        refreshToken: 'synthetic-refresh',
        userId: 'same-user',
        isOnboarded: true,
      );
      await login('old');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final allOldArrived = Completer<void>();
      var oldRequests = 0, refreshes = 0, retries = 0;
      server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/api/auth/refresh') {
          refreshes++;
          if (replace && !replaceAfterRetry) {
            await storage.clearAll();
            await login('replacement');
          }
          request.response.write(
            jsonEncode({
              'accessToken': token('fresh'),
              'refreshToken': 'fresh-refresh',
            }),
          );
        } else if (request.headers.value('authorization') ==
            'Bearer ${token('old')}') {
          oldRequests++;
          if (oldRequests == 3) allOldArrived.complete();
          await allOldArrived.future;
          request.response.statusCode = 401;
          request.response.write('{}');
        } else {
          retries++;
          expect(
            request.headers.value('authorization'),
            'Bearer ${token('fresh')}',
          );
          if (replaceAfterRetry) {
            await storage.clearAll();
            await login('replacement');
          }
          request.response.write(
            jsonEncode(
              request.uri.path == '/api/account'
                  ? {
                      'userId': 'same-user',
                      'encryptedPrivateKey': 'synthetic-ciphertext',
                      'kdf': {
                        'securityVersion': 1,
                        'minimumSecurityVersion': 1,
                        'profileId': 'identity-argon2id-password-v1',
                        'kdfSalt': 'AAECAwQFBgcICQoLDA0ODw',
                        'credentialRevision': 1,
                        'privateKeyWrapRevision': 1,
                      },
                    }
                  : {},
            ),
          );
        }
        await request.response.close();
      });
      final dio = Dio(
        BaseOptions(
          baseUrl: 'http://127.0.0.1:${server.port}',
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
        ),
      );
      dio.interceptors.add(AuthInterceptor(tokenStorage: storage, dio: dio));
      addTearDown(() async {
        dio.close(force: true);
        await server.close(force: true);
      });
      var prompts = 0;
      Future<void> unlock() async {
        const channel = MethodChannel('test/refresh-biometric');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'pending':
              return {
                'id': 'request',
                'mode': 'WEB',
                'verifiedHosts': ['example.com'],
                'usernameOnly': false,
                'remainingMs': 30000,
              };
            case 'beginSourceSession':
              return 1;
            case 'bind':
              return 'binding';
            case 'cancel':
              return null;
            case 'readBiometricMasterKey':
              prompts++;
              return {
                'masterKey': Uint8List.fromList(List.filled(32, 7)),
                'authorizationToken': 'authorization',
              };
            default:
              throw StateError('Unexpected native operation');
          }
        });
        final authority = MemberSyncSessionAuthorityProvider(storage);
        final loader = AutoFillSourceConfigurationLoader(
          authorityProvider: authority,
          accountDatasource: AccountRemoteDatasource(
            dio,
            sessionRevision: () => storage.authorityRevision,
          ),
          config: EnvConfig.staging(apiBaseUrl: 'https://api.example.invalid'),
        );
        final source = AutoFillSourceAccessService(
          channel: channel,
          loadConfiguration: loader.load,
        );
        final requests = AutoFillRequestController(
          channel: channel,
          source: source,
          authority: authority,
        );
        try {
          await requests.poll();
          final key = await requests.readBiometricMasterKey(
            promptTitle: 'Synthetic',
            cancelLabel: 'Cancel',
          );
          expect(key, hasLength(32));
          expect(requests.isAuthorized, isTrue);
          key.fillRange(0, key.length, 0);
        } finally {
          await requests.cancel();
          requests.dispose();
          messenger.setMockMethodCallHandler(channel, null);
        }
      }

      final results = await Future.wait(
        List.generate(3, (i) async {
          try {
            if (biometric && i == 2) {
              await unlock();
            } else {
              await dio.get<void>('/resource/$i');
            }
            return true;
          } on DioException catch (error) {
            expect(CancelToken.isCancel(error), isTrue);
            return false;
          }
        }),
      );
      expect(results, everyElement(!replace));
      expect(refreshes, 1);
      expect(
        retries,
        replace
            ? (replaceAfterRetry ? 1 : 0)
            : biometric
            ? 4
            : 3,
      );
      expect(prompts, biometric ? 1 : 0);
      expect(
        await storage.accessToken,
        token(replace ? 'replacement' : 'fresh'),
      );
    });
  }
}
