import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/config/env_config.dart';
import 'package:mobile_palladin/core/crypto/biometric_profile_binding.dart';
import 'package:mobile_palladin/core/storage/protected_account_unlock_reader.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_session_authority_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/protected-unlock');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final config = EnvConfig.staging(apiBaseUrl: 'https://api.example.invalid');
  const claims = MemberSyncSessionAuthority(
    principalId: 'member',
    organizationId: 'org',
    organizationMembershipGeneration: '3',
    offlinePolicy: '1h',
    offlinePolicyVersion: 2,
  );
  late ProtectedAccountUnlockReader reader;
  late Map<String, Object?> record;
  late int revision;
  Completer<void>? gate;
  Completer<void>? entered;
  setUp(() {
    revision = 1;
    gate = null;
    entered = null;
    record = {
      'profileBinding': biometricProfileBinding(
        flavor: config.flavor,
        apiBaseUrl: config.apiBaseUrl,
        principalId: claims.principalId,
      ),
      'principalId': 'member',
      'organizationId': 'org',
      'organizationMembershipGeneration': '3',
      'offlinePolicy': '1h',
      'offlinePolicyVersion': 2,
      'accountUnlock': {
        'accountId': 'member',
        'encryptedPrivateKey': 'synthetic-ciphertext',
        'kdf': {
          'securityVersion': 1,
          'minimumSecurityVersion': 1,
          'profileId': 'identity-argon2id-password-v1',
          'kdfSalt': 'synthetic-salt',
          'credentialRevision': 1,
          'privateKeyWrapRevision': 1,
        },
      },
    };
    reader = ProtectedAccountUnlockReader(
      config: config,
      channel: channel,
      authority: MemberSyncSessionAuthorityProvider.independent(
        readClaims: () async => claims,
        sessionRevision: () => revision,
      ),
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'sourceConfiguration');
      final expected = call.arguments as Map;
      expect(expected['principalId'], 'member');
      expect(expected['organizationId'], 'org');
      entered?.complete();
      await gate?.future;
      return record;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'reads only protected unlock projection with independent account binding',
    () async {
      final account = await reader.read();
      expect(account.userId, 'member');
      expect(account.encryptedPrivateKey, 'synthetic-ciphertext');
      expect(account.kdf!.credentialRevision, 1);
      expect(account.email, isEmpty);
      expect(account.recoverySalt, isNull);
      expect(account.encryptedPrivateKeyByRecovery, isNull);
    },
  );

  for (final field in [
    'profileBinding',
    'principalId',
    'organizationId',
    'organizationMembershipGeneration',
    'offlinePolicy',
    'offlinePolicyVersion',
  ]) {
    test('rejects protected $field from another authority', () async {
      record[field] = field == 'offlinePolicyVersion' ? 7 : 'different';
      await expectLater(
        reader.read(),
        throwsA(isA<ProtectedAccountUnlockUnavailable>()),
      );
    });
  }

  test(
    'rejects account wrapper mismatch independently of source claims',
    () async {
      (record['accountUnlock'] as Map)['accountId'] = 'other';
      await expectLater(
        reader.read(),
        throwsA(isA<ProtectedAccountUnlockUnavailable>()),
      );
    },
  );

  test(
    'missing or quarantined native source cannot become unlock authority',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      await expectLater(
        reader.read(),
        throwsA(isA<ProtectedAccountUnlockUnavailable>()),
      );
    },
  );

  test('session change during native read rejects old material', () async {
    gate = Completer<void>();
    entered = Completer<void>();
    final result = expectLater(reader.read(), throwsStateError);
    await entered!.future;
    revision++;
    gate!.complete();
    await result;
  });
  test(
    'malformed protected KDF fails without a partial account result',
    () async {
      ((record['accountUnlock'] as Map)['kdf'] as Map)['credentialRevision'] =
          'invalid';
      await expectLater(
        reader.read(),
        throwsA(isA<ProtectedAccountUnlockUnavailable>()),
      );
    },
  );

  test(
    'disabled offline policy never reads protected account material',
    () async {
      final unavailable = ProtectedAccountUnlockReader(
        config: config,
        channel: channel,
        authority: MemberSyncSessionAuthorityProvider.independent(
          readClaims: () async => const MemberSyncSessionAuthority(
            principalId: 'member',
            organizationId: 'org',
            organizationMembershipGeneration: '3',
            offlinePolicy: 'disabled',
            offlinePolicyVersion: 2,
          ),
          sessionRevision: () => revision,
        ),
      );
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => fail('Must not read disabled source'),
      );
      await expectLater(
        unavailable.read(),
        throwsA(isA<ProtectedAccountUnlockUnavailable>()),
      );
    },
  );
}
