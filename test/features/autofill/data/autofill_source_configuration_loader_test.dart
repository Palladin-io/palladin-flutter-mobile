import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
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
  late AccountRemoteDatasource datasource;
  late AutoFillSourceConfigurationLoader loader;
  late List<Map<Object?, Object?>> nativeConfigurations;
  setUp(() async {
    revision = 1;
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
