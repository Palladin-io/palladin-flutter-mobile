import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/config/env_config.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/core/storage/biometric_key_store.dart';
import 'package:mobile_palladin/core/storage/biometric_key_storage.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_request_controller.dart';

import 'package:mobile_palladin/features/autofill/data/autofill_source_access_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_session_authority_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Android app biometric prompt does not wait for AutoFill binding',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await getIt.reset();
      addTearDown(getIt.reset);
      FlutterSecureStorage.setMockInitialValues({
        BiometricKeyStorage.enrolledMarkerKey: '1',
      });
      configureDependencies(EnvConfig.local());
      await getIt.unregister<AutoFillRequestController>();
      final pending = Completer<AutoFillSourceConfiguration>();
      const authority = MemberSyncSessionAuthority(
        principalId: 'p',
        organizationId: 'o',
        organizationMembershipGeneration: '1',
        offlinePolicy: '24h',
        offlinePolicyVersion: 1,
      );
      const requestChannel = MethodChannel('test/biometric-request');
      final requestCalls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(requestChannel, (call) async {
        requestCalls.add(call.method);
        return switch (call.method) {
          'pending' => {
            'id': 'request',
            'mode': 'WEB',
            'verifiedHosts': ['example.test'],
            'usernameOnly': false,
            'remainingMs': 30000,
          },
          'beginSourceSession' => 1,
          'bind' => 'bound',
          'readBiometricMasterKey' => {
            'masterKey': Uint8List(32),
            'authorizationToken': 'auth',
          },
          _ => null,
        };
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(requestChannel, null),
      );
      final source = AutoFillSourceAccessService(
        channel: requestChannel,
        loadConfiguration: () => pending.future,
      );
      final requests = AutoFillRequestController(
        source: source,
        channel: requestChannel,
        authority: MemberSyncSessionAuthorityProvider.independent(
          readClaims: () async => authority,
          sessionRevision: () => 0,
        ),
      );
      getIt.registerSingleton<AutoFillRequestController>(requests);
      addTearDown(requests.dispose);
      await requests.poll();
      var nativePrompts = 0;
      final localRead = Completer<String>();
      final promptStarted = Completer<void>();
      const channel = MethodChannel('biometric_storage');
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'init') return true;
        if (call.method == 'read') {
          nativePrompts++;
          promptStarted.complete();
          return localRead.future;
        }
        throw StateError('Unexpected biometric operation');
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final operation = getIt<BiometricKeyStore>().unlockKey(
        const BiometricPromptCopy(
          promptTitle: 'Unlock',
          enrollTitle: 'Enroll',
          accessTitle: 'Read',
          cancelLabel: 'Cancel',
        ),
      );
      try {
        await promptStarted.future.timeout(const Duration(seconds: 1));
        expect(
          nativePrompts,
          1,
          reason:
              'Local biometric authorization must not wait for network-bound AutoFill initialization',
        );
        expect(requestCalls, isNot(contains('readBiometricMasterKey')));
        expect(requests.isAuthenticating, isTrue);
        expect(requests.isAuthorized, isFalse);
        expect(requests.hasBoundRequest, isFalse);
      } finally {
        localRead.complete(base64Encode(Uint8List(32)));
        pending.complete(
          AutoFillSourceConfiguration(
            authority: authority,
            profileBinding: 'a' * 64,
            accountUnlock: const {},
            validateCurrent: () {},
          ),
        );
        final key = await operation;
        key?.fillRange(0, key.length, 0);
      }
    },
  );
}
