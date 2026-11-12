import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile_palladin/core/storage/secure_token_storage.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_request_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/config/env_config.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_source_access_service.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_source_configuration_loader.dart';
import 'package:mobile_palladin/features/unlock/data/datasources/account_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_session_authority_provider.dart';

class _LoopbackBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _LoopbackBinding();
  const channel = MethodChannel('test/source-loader');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const authority = MemberSyncSessionAuthority(
    principalId: 'member',
    organizationId: 'org',
    organizationMembershipGeneration: '1',
    offlinePolicy: '1h',
    offlinePolicyVersion: 1,
  );
  const kdf = <String, Object>{
    'securityVersion': 1,
    'minimumSecurityVersion': 1,
    'profileId': 'identity-argon2id-password-v1',
    'kdfSalt': 'AAECAwQFBgcICQoLDA0ODw',
    'credentialRevision': 1,
    'privateKeyWrapRevision': 1,
  };
  late HttpServer server;
  late Dio dio;
  late Completer<void> release;
  late Completer<void> arrived;
  late Map<String, Object?> response;
  late int requestCount;
  late int revision;
  Future<void> Function()? beforeResponse;
  late AccountRemoteDatasource datasource;
  late AutoFillSourceConfigurationLoader loader;
  late List<Map<Object?, Object?>> nativeConfigurations;
  setUp(() async {
    revision = 1;
    beforeResponse = null;
    requestCount = 0;
    release = Completer<void>();
    arrived = Completer<void>();
    nativeConfigurations = [];
    response = {
      'userId': 'member',
      'email': 'excluded@example.invalid',
      'encryptedPrivateKey': 'synthetic-ciphertext',
      'kdf': kdf,
      'encryptedPrivateKeyByRecovery': 'excluded-recovery',
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requestCount++;
      if (!arrived.isCompleted) arrived.complete();
      await release.future;
      await beforeResponse?.call();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}'));
    datasource = AccountRemoteDatasource(dio, sessionRevision: () => revision);
    loader = AutoFillSourceConfigurationLoader(
      authorityProvider: MemberSyncSessionAuthorityProvider.independent(
        readClaims: () async => authority,
        sessionRevision: () => revision,
      ),
      accountDatasource: datasource,
      config: EnvConfig.staging(apiBaseUrl: 'https://api.example.invalid'),
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'beginSourceSession');
      nativeConfigurations.add(
        Map<Object?, Object?>.from(call.arguments as Map),
      );
      return 1;
    });
  });
  tearDown(() async {
    if (!release.isCompleted) release.complete();
    dio.close(force: true);
    await server.close(force: true);
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'cold availability and overlapping unlock use one real HTTP request and minimal native projection',
    () async {
      final source = AutoFillSourceAccessService(
        channel: channel,
        loadConfiguration: loader.load,
      );
      final first = source.biometricSourceTicket();
      final second = source.biometricSourceTicket();
      await arrived.future;
      final unlockAccount = datasource.getUnlockAccount();
      release.complete();
      await Future.wait([first, second, unlockAccount]);
      expect(requestCount, 1);
      expect(nativeConfigurations, hasLength(1));
      final payload = nativeConfigurations.single;
      expect(payload['principalId'], 'member');
      expect(
        payload['profileBinding'],
        '101ab37f1c7988221af56cce3c3b4cc3b07489ebff310a6b6900d0558e1d0856',
      );
      expect(payload['accountUnlock'], {
        'accountId': 'member',
        'encryptedPrivateKey': 'synthetic-ciphertext',
        'kdf': kdf,
      });
      await datasource.getAccount();
      expect(
        requestCount,
        2,
        reason: 'Completed account metadata must not become an unbounded cache',
      );
    },
  );

  for (final scenario in [
    'refresh',
    'replacement',
    'scope',
    'repeated-refresh',
  ]) {
    test(
      'request biometric cold source handles $scenario without stale auth',
      () async {
        FlutterSecureStorage.setMockInitialValues({});
        final tokens = SecureTokenStorage(const FlutterSecureStorage());
        String token({String organization = 'org'}) =>
            'synthetic.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'member', 'org_id': organization, 'authz_ver': '1', 'org_offline_policy': 1, 'org_offline_policy_ver': 1})))}.synthetic';
        Future<void> login() => tokens.saveTokens(
          accessToken: token(),
          refreshToken: 'synthetic-refresh',
          userId: 'member',
          isOnboarded: true,
        );
        await login();
        final provider = MemberSyncSessionAuthorityProvider(tokens);
        loader = AutoFillSourceConfigurationLoader(
          authorityProvider: provider,
          accountDatasource: datasource,
          config: EnvConfig.staging(apiBaseUrl: 'https://api.example.invalid'),
        );
        beforeResponse = () async {
          if (requestCount != 1 && scenario != 'repeated-refresh') return;
          if (scenario == 'replacement') {
            await tokens.clearAll();
            await login();
          } else {
            await tokens.updateTokens(
              accessToken: token(
                organization: scenario == 'scope' ? 'other-org' : 'org',
              ),
              refreshToken: 'synthetic-refresh',
            );
          }
        };
        var prompts = 0;
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
              nativeConfigurations.add(
                Map<Object?, Object?>.from(call.arguments as Map),
              );
              return 1;
            case 'cancel':
              return null;
            case 'bind':
              return 'binding';
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
        final source = AutoFillSourceAccessService(
          channel: channel,
          loadConfiguration: loader.load,
        );
        final controller = AutoFillRequestController(
          source: source,
          authority: provider,
          channel: channel,
        );
        addTearDown(controller.dispose);
        await controller.poll();
        final unlocking = controller.readBiometricMasterKey(
          promptTitle: 'Synthetic',
          cancelLabel: 'Cancel',
        );
        final result = scenario == 'refresh'
            ? expectLater(unlocking, completion(hasLength(32)))
            : expectLater(unlocking, throwsStateError);
        await arrived.future;
        release.complete();
        await result;
        expect(prompts, scenario == 'refresh' ? 1 : 0);
        expect(controller.isAuthorized, scenario == 'refresh');
        expect(nativeConfigurations, hasLength(scenario == 'refresh' ? 1 : 0));
        expect(
          requestCount,
          scenario == 'refresh' || scenario == 'repeated-refresh' ? 2 : 1,
        );
      },
    );
  }

  test(
    'account envelope cannot be bound to a different independently authenticated principal',
    () async {
      response['userId'] = 'another-member';
      final loading = loader.load();
      final rejected = expectLater(
        loading,
        throwsA(
          isA<AutoFillSourceConfigurationException>().having(
            (e) => e.kind,
            'kind',
            AutoFillSourceConfigurationFailure.accountMismatch,
          ),
        ),
      );
      await arrived.future;
      release.complete();
      await rejected;
    },
  );

  test(
    'session replacement while HTTP is pending cannot publish a source',
    () async {
      final source = AutoFillSourceAccessService(
        channel: channel,
        loadConfiguration: loader.load,
      );
      final loading = source.biometricSourceTicket();
      final rejected = expectLater(loading, throwsStateError);
      await arrived.future;
      revision++;
      release.complete();
      await rejected;
      expect(nativeConfigurations, isEmpty);
    },
  );

  test(
    'configuration remains fenced after load until native publication',
    () async {
      final loading = loader.load();
      await arrived.future;
      release.complete();
      final loaded = await loading;
      loaded.validateCurrent();
      revision++;
      expect(loaded.validateCurrent, throwsStateError);
    },
  );

  test('account without unlock material cannot activate provider', () async {
    response.remove('kdf');
    final loading = loader.load();
    final rejected = expectLater(
      loading,
      throwsA(
        isA<AutoFillSourceConfigurationException>().having(
          (e) => e.kind,
          'kind',
          AutoFillSourceConfigurationFailure.missingUnlockMaterial,
        ),
      ),
    );
    await arrived.future;
    release.complete();
    await rejected;
  });
}
