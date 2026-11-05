import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/crypto/envelope/envelope_contract.dart';
import 'package:mobile_palladin/core/crypto/recipient_key_wrapper.dart';
import 'package:mobile_palladin/core/permissions.dart';
import 'package:mobile_palladin/core/storage/account_secret_store.dart';
import 'package:mobile_palladin/features/security_upgrade/data/security_upgrade_remote_datasource.dart';
import 'package:mobile_palladin/features/security_upgrade/data/security_upgrade_service.dart';
import 'package:mobile_palladin/features/unlock/data/models/account_response.dart';
import 'package:mobile_palladin/features/unlock/data/services/identity_kdf_service.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/models/encrypted_vault_summary_model.dart';
import 'package:mobile_palladin/features/vault/data/services/agent_message_key_migration_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../support/native_sodium.dart';

import '../../support/legacy_key_wrapper.dart';

class _Remote extends Mock implements SecurityUpgradeRemoteDatasource {}

class _Vaults extends Mock implements VaultRemoteDatasource {}

class _Secrets extends Mock implements AccountSecretStore {}

class _MessageKeys extends Mock implements AgentMessageKeyMigrationService {}

const _org = '11111111-1111-4111-8111-111111111111';
const _vault = '22222222-2222-4222-8222-222222222222';
const _member = '44444444-4444-4444-8444-444444444444';

void main() {
  late SodiumSumo sodium;
  late _Remote remote;
  late _Vaults vaults;
  late _Secrets secrets;
  late _MessageKeys messageKeys;
  late String? token;
  late SecurityUpgradeService service;
  final calls = <String>[];

  setUpAll(() async {
    sodium = await loadTestSodium();
    registerFallbackValue(<String, Object?>{});
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(0);
  });

  setUp(() {
    calls.clear();
    remote = _Remote();
    vaults = _Vaults();
    secrets = _Secrets();
    messageKeys = _MessageKeys();
    token = _token(Permissions.vaultManage);
    when(() => secrets.write(any(), any())).thenAnswer((_) async {
      calls.add('store-secret');
    });
    service = SecurityUpgradeService(
      remote: remote,
      vaults: vaults,
      identityKdf: IdentityKdfService(sodiumLoader: () async => sodium),
      accountSecrets: secrets,
      messageKeys: messageKeys,
      accessToken: () async => token,
      sodiumLoader: () async => sodium,
    );
  });

  test(
    'commit stores the Secret Key first and uploads no secret material',
    () async {
      Map<String, Object?>? body;
      when(() => remote.upgrade(any())).thenAnswer((call) async {
        calls.add('upgrade');
        body = call.positionalArguments.single as Map<String, Object?>;
        return const SecurityUpgradeCommit(memberKeyVersion: 2);
      });
      final legacy = sodium.randombytes.buf(32);
      final phrase = List.generate(24, (i) => 'abandon');

      final keys = await service.commit(
        migrationId: '0f0e0d0c-0b0a-4908-8706-050403020100',
        password: 'correct horse battery staple',
        account: const AccountResponse(
          userId: _member,
          memberKeyVersion: 1,
          kdf: IdentityKdfMetadata(
            securityVersion: 1,
            minimumSecurityVersion: 1,
            profileId: IdentityKdfProfile.id,
            kdfSalt: 'AAECAwQFBgcICQoLDA0ODw',
            credentialRevision: 3,
            privateKeyWrapRevision: 4,
          ),
        ),
        legacyPrivateKey: legacy,
        recoveryMnemonic: phrase,
      );
      addTearDown(keys.dispose);

      expect(calls, ['store-secret', 'upgrade']);
      expect(body!['memberPublicKeySuiteId'], 'palladin-xwing-v1');
      expect(
        base64Url.decode(
          base64Url.normalize(body!['memberPublicKey'] as String),
        ),
        hasLength(1216),
      );
      expect(body!['securityVersion'], 2);
      final wire = jsonEncode(body);
      for (final secret in [
        keys.accountSecret!,
        keys.masterKey,
        keys.memberPrivateKey,
        legacy,
      ]) {
        expect(wire, isNot(contains(b64url(secret))));
      }
      expect(wire, isNot(contains(phrase.join(' '))));
      expect(keys.memberKeyVersion, 2);
    },
  );

  test(
    'legacy member envelopes are re-wrapped to the new X-Wing key',
    () async {
      final legacyPair = sodium.crypto.box.keyPair();
      final legacyPrivate = legacyPair.secretKey.extractBytes();
      final vaultKey = sodium.randombytes.buf(32);
      final legacyContext = WrapperContext(
        suiteId: WrapperSuite.x25519SealedBoxV1,
        purpose: WrapperPurpose.memberVaultKey,
        scope: EnvelopeScope(
          organizationId: EnvelopeId.parse(_org),
          vaultId: EnvelopeId.parse(_vault),
          memberId: EnvelopeId.parse(_member),
        ),
        resourceRevision: 1,
        wrappedKeyVersion: 3,
        memberKeyGeneration: 5,
        recipientKeyKind: 5,
        recipientKeyVersion: 1,
        recipientFingerprint: recipientFingerprint(
          WrapperSuite.x25519SealedBoxV1,
          5,
          legacyPair.publicKey,
        ),
      );
      final sealed = sealLegacyForTest(
        sodium,
        key: vaultKey,
        context: legacyContext,
        recipientPublicKey: legacyPair.publicKey,
      );
      final envelope = {
        'wrappedVaultKey': {
          'descriptor': {
            ...legacyContext.toDescriptor().toJson(),
            'purpose': 'memberVaultKey',
            'recipientKeyKind': 5,
          },
          'encodedSealedKeyPackage': b64url(sealed),
        },
      };
      when(
        () => vaults.listEncryptedVaults(offset: any(named: 'offset')),
      ).thenAnswer(
        (_) async => EncryptedVaultPage(vaults: [_summary(envelope)], total: 1),
      );
      Map<String, Object?>? replaced;
      when(() => remote.replaceMemberEnvelope(_vault, any())).thenAnswer((
        call,
      ) async {
        replaced = call.positionalArguments[1] as Map<String, Object?>;
      });
      when(() => remote.report()).thenAnswer(
        (_) async => const KeyMigrationReport(
          memberEnvelopesPendingRewrap: 0,
          agentEnvelopesOnNonCurrentSuite: 0,
        ),
      );
      when(() => remote.deleteLegacyMemberKey(1)).thenAnswer((_) async => true);
      final seed = sodium.randombytes.buf(32);
      final keys = UpgradedAccountKeys(
        accountId: _member,
        email: '',
        masterKey: Uint8List(32),
        memberPrivateKey: seed,
        memberKeyVersion: 2,
        legacyPrivateKey: legacyPrivate,
        legacyKeyVersion: 1,
      );

      await service.rewrapMemberEnvelopes(keys);
      await service.cleanUp(keys);

      expect(replaced!['expectedRecipientKeyVersion'], 1);
      final wrapped = Map<String, dynamic>.from(
        replaced!['wrappedVaultKey'] as Map,
      );
      final descriptor =
          (wrapped['wrappedVaultKey'] as Map)['descriptor'] as Map;
      expect(descriptor['wrapperSuiteId'], 'palladin-xwing-v1');
      expect(descriptor['recipientKeyKind'], 'memberEncryption');
      expect(descriptor['memberKeyGeneration'], 5);
      final reopened =
          await VaultRotationCryptoService(
            sodiumLoader: () async => sodium,
          ).openMemberVaultKey(
            jsonDecode(jsonEncode(wrapped)) as Map<String, dynamic>,
            seed,
            expectedVaultId: _vault,
          );
      expect(reopened, vaultKey);
      verify(() => remote.deleteLegacyMemberKey(1)).called(1);
    },
  );

  test('the legacy key stays while another organization is pending', () async {
    when(
      () => vaults.listEncryptedVaults(offset: any(named: 'offset')),
    ).thenAnswer((_) async => const EncryptedVaultPage(vaults: [], total: 0));
    when(() => remote.report()).thenAnswer(
      (_) async => const KeyMigrationReport(
        memberEnvelopesPendingRewrap: 0,
        accountMemberEnvelopesPendingRewrap: 2,
        agentEnvelopesOnNonCurrentSuite: 0,
      ),
    );
    final keys = UpgradedAccountKeys(
      accountId: _member,
      email: '',
      masterKey: Uint8List(32),
      memberPrivateKey: sodium.randombytes.buf(32),
      memberKeyVersion: 2,
      legacyPrivateKey: Uint8List(32),
      legacyKeyVersion: 1,
    );

    await service.rewrapMemberEnvelopes(keys);
    await service.cleanUp(keys);

    verifyNever(() => remote.deleteLegacyMemberKey(any()));
  });

  group('resume per organization', () {
    void report({
      int current = 0,
      int account = 0,
      List<String> organizations = const [],
    }) => when(() => remote.report()).thenAnswer(
      (_) async => KeyMigrationReport(
        memberEnvelopesPendingRewrap: current,
        accountMemberEnvelopesPendingRewrap: account,
        organizationIdsPendingRewrap: organizations,
        agentEnvelopesOnNonCurrentSuite: 0,
      ),
    );

    test('an organization with pending envelopes resumes', () async {
      report(current: 1, account: 3, organizations: [_org, 'other']);
      expect(await service.hasPendingWorkHere(), isTrue);
    });

    test('an organization already re-wrapped skips the screen', () async {
      report(account: 2, organizations: ['other']);
      expect(await service.hasPendingWorkHere(), isFalse);
    });

    test('nothing pending anywhere resumes to delete the legacy key', () async {
      report();
      expect(await service.hasPendingWorkHere(), isTrue);
    });
  });

  group('Vault Agent message keys', () {
    Map<String, dynamic> vault(String id, String? suite) => {
      'id': id,
      'vaultAgentMessageKeySuiteId': ?suite,
    };

    setUp(() {
      when(
        () => vaults.listEncryptedVaults(offset: any(named: 'offset')),
      ).thenAnswer(
        (_) async => EncryptedVaultPage(
          vaults: [
            _summaryWithId('a'),
            _summaryWithId('b'),
            _summaryWithId('c'),
          ],
          total: 3,
        ),
      );
      when(
        () => vaults.getEncryptedVault('a'),
      ).thenAnswer((_) async => vault('a', 'palladin-x25519-sealed-box-v1'));
      when(
        () => vaults.getEncryptedVault('b'),
      ).thenAnswer((_) async => vault('b', 'palladin-xwing-v1'));
      when(
        () => vaults.getEncryptedVault('c'),
      ).thenAnswer((_) async => vault('c', null));
    });

    test('a Vault manager migrates every non-active Vault and skips a '
        'forbidden one', () async {
      when(
        () => messageKeys.migrate(
          vaultId: 'a',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => messageKeys.migrate(
          vaultId: 'c',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(),
          response: Response(requestOptions: RequestOptions(), statusCode: 403),
        ),
      );

      expect(await service.migrateAgentMessageKeys(Uint8List(32)), 1);
      verifyNever(
        () => messageKeys.migrate(
          vaultId: 'b',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      );
    });

    test('a member without VaultManage migrates nothing', () async {
      token = _token(Permissions.vaultCreate);
      expect(await service.migrateAgentMessageKeys(Uint8List(32)), 0);
      verifyZeroInteractions(messageKeys);
      verifyNever(
        () => vaults.listEncryptedVaults(offset: any(named: 'offset')),
      );
    });
  });
}

String _token(int permissions) {
  String part(Map<String, Object> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.'
      '${part({'org_id': _org, 'permissions': '$permissions'})}.signature';
}

EncryptedVaultSummaryModel _summaryWithId(String id) =>
    _summary(const <String, dynamic>{}, id: id);

EncryptedVaultSummaryModel _summary(
  Map<String, dynamic> memberVaultKey, {
  String id = _vault,
}) => EncryptedVaultSummaryModel.fromJson({
  'id': id,
  'isDefault': false,
  'protocolVersion': 2,
  'memberSequence': '1',
  'discoverySequence': '1',
  'memberKeyGeneration': 5,
  'memberVaultMetadata': <String, dynamic>{},
  'memberVaultKey': memberVaultKey,
  'currentKeyEpoch': <String, dynamic>{},
  'discoveryKey': <String, dynamic>{},
  'vaultPrivateKeys': [<String, dynamic>{}, <String, dynamic>{}],
  'createdAt': '2026-11-04T00:00:00Z',
  'updatedAt': '2026-11-04T00:00:00Z',
  'memberCount': 1,
  'entryCount': 0,
  'activeGrantCount': 0,
});
