import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/crypto/kem/xwing.dart';
import 'package:mobile_palladin/core/crypto/recipient_key_wrapper.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_rotation_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/models/vault_rotation_models.dart';
import 'package:mobile_palladin/features/vault/data/services/agent_message_key_migration_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_bytes.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_signature_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../../../support/native_sodium.dart';

class _Rotations extends Mock implements VaultRotationRemoteDatasource {}

class _Vaults extends Mock implements VaultRemoteDatasource {}

const _org = '11111111-1111-4111-8111-111111111111';
const _member = '22222222-2222-4222-8222-222222222222';
const _vaultId = '33333333-3333-4333-8333-333333333333';
const _rotationId = '44444444-4444-4444-8444-444444444444';
const _purposeNames = {
  3: 'vaultAgentMessagePrivateKey',
  4: 'vaultManifestSigningPrivateKey',
};

const _base = VaultKeyEpochModel(
  vaultKeyVersion: 1,
  vdkVersion: 1,
  agentMessageKeyVersion: 1,
  manifestSigningKeyVersion: 1,
);
const _target = VaultKeyEpochModel(
  vaultKeyVersion: 1,
  vdkVersion: 1,
  agentMessageKeyVersion: 2,
  manifestSigningKeyVersion: 1,
);

const _rotation = VaultRotationModel(
  id: _rotationId,
  vaultId: _vaultId,
  status: 'Pending',
  scope: ['AgentMessage'],
  baseMemberKeyGeneration: 1,
  targetMemberKeyGeneration: 1,
  baseKeyEpoch: _base,
  targetKeyEpoch: _target,
);

void main() {
  late SodiumSumo sodium;
  late _Rotations rotations;
  late _Vaults vaults;
  late Uint8List memberSeed;
  late Map<String, dynamic> vault;
  late String manifestSigningPublicKey;
  late AgentMessageKeyMigrationService service;

  setUpAll(() async {
    sodium = await loadTestSodium();
    registerFallbackValue(CancelToken());
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() async {
    rotations = _Rotations();
    vaults = _Vaults();
    memberSeed = XWing(sodium).generateSeed();
    final crypto = VaultCryptoService(sodiumLoader: () async => sodium);
    final bundle = await crypto.createVaultBundle(
      organizationId: _org,
      memberId: _member,
      memberKeyVersion: 1,
      vaultId: _vaultId,
      memberPrivateKey: memberSeed,
      name: 'Ops',
      grantMode: GrantMode.full,
    );
    final request =
        jsonDecode(jsonEncode(bundle.request.toJson())) as Map<String, dynamic>;
    manifestSigningPublicKey =
        (request['vaultManifestSigningPublicKey'] as Map)['encodedPublicKey']
            as String;
    vault = {
      'id': _vaultId,
      'organizationId': _org,
      'memberKeyGeneration': 1,
      'currentKeyEpoch': request['currentKeyEpoch'],
      'memberVaultMetadata': request['memberVaultMetadata'],
      'memberVaultKey': request['creatorVaultKey'],
      'discoveryKey': request['discoveryKey'],
      'vaultPrivateKeys': [
        for (final envelope in request['vaultPrivateKeys'] as List)
          {
            ...envelope as Map<String, dynamic>,
            'descriptor': {
              ...envelope['descriptor'] as Map<String, dynamic>,
              'purpose': _purposeNames[envelope['descriptor']['purpose']],
            },
          },
      ],
      'vaultAgentMessagePublicKey': request['vaultAgentMessagePublicKey'],
      'vaultAgentMessageKeySuiteId': 'palladin-x25519-sealed-box-v1',
    };
    when(
      () => vaults.getEncryptedVault(_vaultId),
    ).thenAnswer((_) async => vault);
    when(() => rotations.claim(_vaultId, _rotationId, any())).thenAnswer(
      (_) async => const VaultRotationClaimModel(
        organizationId: _org,
        rotation: _rotation,
        fencingToken: 'fence',
        currentMemberVaultKey: {},
        currentDiscoveryKey: {},
        currentVaultPrivateKeys: [],
        pendingVaultPrivateKeys: [],
        preparedMaterialReset: false,
      ),
    );
    when(
      () => rotations.prepare(_vaultId, _rotationId, 'fence', any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => rotations.commit(_vaultId, _rotationId, 'fence', any()),
    ).thenAnswer((_) async => const RotationCommitResult(committed: true));
    service = AgentMessageKeyMigrationService(
      rotations: rotations,
      vaults: vaults,
      vaultCrypto: crypto,
      rotationCrypto: VaultRotationCryptoService(
        sodiumLoader: () async => sodium,
      ),
      sodiumLoader: () async => sodium,
    );
  });

  test('a current message key needs no migration (409)', () async {
    when(
      () => rotations.startAgentMessageKeyMigration(_vaultId, any()),
    ).thenAnswer((_) async => null);

    expect(
      await service.migrate(vaultId: _vaultId, memberPrivateKey: memberSeed),
      isFalse,
    );
    verifyNever(() => rotations.claim(any(), any(), any()));
  });

  test('publishes an X-Wing message key under the unchanged VK and '
      'provisions only Agents on the active suite', () async {
    when(
      () => rotations.startAgentMessageKeyMigration(_vaultId, any()),
    ).thenAnswer((_) async => _rotation);
    final xwing = XWing(sodium);
    final agentSigning = sodium.crypto.sign.keyPair();
    addTearDown(agentSigning.dispose);
    final legacyAgent = sodium.crypto.box.keyPair();
    addTearDown(legacyAgent.dispose);
    when(() => rotations.agents(_vaultId, any(), any())).thenAnswer(
      (_) async => RotationPage(
        items: [
          RotationAgentRecipient(
            agentId: '55555555-5555-4555-8555-555555555555',
            publicKey: base64.encode(
              xwing.publicKeyFromSeed(xwing.generateSeed()),
            ),
            keySuite: WrapperSuite.xwingV1,
            ed25519PublicKey: base64.encode(agentSigning.publicKey),
            recipientKeyVersion: 2,
          ),
          RotationAgentRecipient(
            agentId: '66666666-6666-4666-8666-666666666666',
            publicKey: base64.encode(legacyAgent.publicKey),
            keySuite: WrapperSuite.x25519SealedBoxV1,
            ed25519PublicKey: base64.encode(agentSigning.publicKey),
            recipientKeyVersion: 1,
          ),
        ],
      ),
    );

    expect(
      await service.migrate(vaultId: _vaultId, memberPrivateKey: memberSeed),
      isTrue,
    );

    final batch =
        verify(
              () => rotations.prepare(
                _vaultId,
                _rotationId,
                'fence',
                captureAny(),
                any(),
              ),
            ).captured.single
            as Map<String, dynamic>;
    verify(
      () => rotations.commit(_vaultId, _rotationId, 'fence', any()),
    ).called(1);
    expect(batch.keys, {
      'vaultPrivateKeys',
      'vaultAgentMessagePublicKey',
      'agentDiscoveries',
    });
    final anchor = batch['vaultAgentMessagePublicKey'] as Map;
    expect(anchor['schemeId'], 'palladin-xwing-v1');
    expect(anchor['keyVersion'], 2);

    final opened = await VaultCryptoService(
      sodiumLoader: () async => sodium,
    ).openVaultProjection(json: vault, memberPrivateKey: memberSeed);
    final envelope = Map<String, dynamic>.from(
      (batch['vaultPrivateKeys'] as List).single as Map,
    );
    final descriptor = envelope['descriptor'] as Map;
    expect(descriptor['resourceRevision'], '2');
    expect(descriptor['keyVersion'], 2);
    expect((descriptor['binding'] as Map)['wrappingVaultKeyVersion'], 1);
    final messageSeed =
        await VaultRotationCryptoService(
          sodiumLoader: () async => sodium,
        ).openCanonicalAgentMessagePrivateKey(
          envelope,
          opened.vaultKey,
          expectedKeyVersion: 2,
        );
    expect(
      anchor['encodedPublicKey'],
      VaultProtocolBytes.base64UrlEncode(xwing.publicKeyFromSeed(messageSeed)),
    );

    final discoveries = batch['agentDiscoveries'] as List;
    expect(discoveries, hasLength(1), reason: 'legacy Agent is skipped');
    final manifest = Map<String, Object?>.from(
      (discoveries.single as Map)['manifest'] as Map,
    );
    expect(manifest['vaultAgentMessageKeySuiteId'], 'palladin-xwing-v1');
    expect(manifest['agentMessageKeyVersion'], 2);
    expect(manifest['vaultAgentMessagePublicKey'], anchor['encodedPublicKey']);
    expect(manifest['vaultSigningPublicKey'], manifestSigningPublicKey);
    expect(
      await VaultProtocolSignatureService(
        sodiumLoader: () async => sodium,
      ).verify(
        domainPrefix: 'PLDNV2SIG:VAULT-MANIFEST:',
        unsignedObject: Map.of(manifest)..remove('signature'),
        signature: manifest['signature']! as String,
        publicKey: VaultProtocolBytes.base64UrlDecode(manifestSigningPublicKey),
      ),
      isTrue,
    );
  });

  test('a plan that does not rotate only the message key is refused', () async {
    when(
      () => rotations.startAgentMessageKeyMigration(_vaultId, any()),
    ).thenAnswer(
      (_) async => const VaultRotationModel(
        id: _rotationId,
        vaultId: _vaultId,
        status: 'Pending',
        scope: ['AgentMessage', 'VaultKey'],
        baseMemberKeyGeneration: 1,
        targetMemberKeyGeneration: 2,
        baseKeyEpoch: _base,
        targetKeyEpoch: _target,
      ),
    );
    await expectLater(
      service.migrate(vaultId: _vaultId, memberPrivateKey: memberSeed),
      throwsA(isA<Exception>()),
    );
    verifyNever(() => rotations.prepare(any(), any(), any(), any(), any()));
  });
}
