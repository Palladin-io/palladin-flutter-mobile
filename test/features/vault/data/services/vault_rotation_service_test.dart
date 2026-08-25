import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_rotation_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/models/vault_rotation_models.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_aad.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_service.dart';

class _Remote extends Mock implements VaultRotationRemoteDatasource {}

class _Crypto extends Mock implements VaultRotationCryptoService {}

void main() {
  late _Remote remote;
  late _Crypto crypto;
  late VaultRotationService service;
  late VaultRotationModel rotation;
  late VaultRotationClaimModel claim;

  setUpAll(() {
    registerFallbackValue(CancelToken());
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(VaultAadProfile.vaultDiscoveryKey);
  });

  setUp(() {
    remote = _Remote();
    crypto = _Crypto();
    service = VaultRotationService(remote: remote, crypto: crypto);
    rotation = _rotation();
    claim = _claim(rotation);
    when(() => remote.listPending(any())).thenAnswer((_) async => [rotation]);
    when(
      () => remote.claim(rotation.vaultId, rotation.id, any()),
    ).thenAnswer((_) async => claim);
    when(
      () => crypto.openMemberVaultKey(any(), any()),
    ).thenAnswer((_) async => Uint8List(32));
    when(() => crypto.generateKeys()).thenAnswer(
      (_) async => VaultRotationKeys(
        vaultKey: Uint8List(32),
        vdk: Uint8List.fromList(List.filled(32, 7)),
        agentMessagePrivateKey: Uint8List.fromList(List.filled(32, 8)),
        manifestSigningSeed: Uint8List.fromList(List.filled(32, 9)),
      ),
    );
    when(
      () => crypto.openDiscoveryKey(any(), any()),
    ).thenAnswer((_) async => Uint8List.fromList(List.filled(32, 3)));
    when(() => crypto.openPrivateKey(any(), any())).thenAnswer((
      invocation,
    ) async {
      final envelope = invocation.positionalArguments.first as Map;
      return Uint8List.fromList(
        List.filled(32, envelope['privateKeyKind'] == 1 ? 4 : 5),
      );
    });
    when(
      () => crypto.encryptKeyMaterial(
        source: any(named: 'source'),
        profile: any(named: 'profile'),
        plaintext: any(named: 'plaintext'),
        targetVaultKey: any(named: 'targetVaultKey'),
        targetVersion: any(named: 'targetVersion'),
        targetGeneration: any(named: 'targetGeneration'),
        targetVaultKeyVersion: any(named: 'targetVaultKeyVersion'),
      ),
    ).thenAnswer((_) async => {'ciphertext': 'opaque'});
    when(
      () => remote.prepare(rotation.vaultId, rotation.id, any(), any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => remote.discoveries(
        rotation.vaultId,
        rotation.id,
        any(),
        any(),
        any(),
      ),
    ).thenAnswer((_) async => const RotationPage(items: []));
    when(
      () =>
          remote.fullGrants(rotation.vaultId, rotation.id, any(), any(), any()),
    ).thenAnswer((_) async => const RotationPage(items: []));
    when(
      () => remote.agents(rotation.vaultId, any(), any()),
    ).thenAnswer((_) async => const RotationPage(items: []));
    when(
      () => remote.commit(rotation.vaultId, rotation.id, any(), any()),
    ).thenAnswer((_) async => const RotationCommitResult(committed: true));
  });

  test('claims, seeds, processes bounded pages and commits', () async {
    await service.resumeAfterUnlock(
      memberId: '44444444-4444-4444-8444-444444444444',
      memberPrivateKey: Uint8List(32),
    );

    verify(() => remote.claim(rotation.vaultId, rotation.id, any())).called(1);
    verify(
      () => remote.prepare(
        rotation.vaultId,
        rotation.id,
        '33333333-3333-4333-8333-333333333333',
        any(),
        any(),
      ),
    ).called(1);
    verify(
      () => remote.commit(
        rotation.vaultId,
        rotation.id,
        '33333333-3333-4333-8333-333333333333',
        any(),
      ),
    ).called(1);
  });

  test('fails closed when claim changes the listed plan', () async {
    final changed = _rotation(targetGeneration: 9);
    when(
      () => remote.claim(rotation.vaultId, rotation.id, any()),
    ).thenAnswer((_) async => _claim(changed));

    await expectLater(
      service.resumeAfterUnlock(
        memberId: '44444444-4444-4444-8444-444444444444',
        memberPrivateKey: Uint8List(32),
      ),
      throwsA(
        isA<VaultRotationException>().having(
          (error) => error.code,
          'code',
          'rotation-plan-changed',
        ),
      ),
    );
    verifyNever(() => crypto.generateKeys());
    verifyNever(() => remote.commit(any(), any(), any(), any()));
  });

  test('signing-only rotation re-signs every active FULL wrapper', () async {
    rotation = _manifestSigningRotation();
    claim = _claim(rotation);
    when(() => remote.listPending(any())).thenAnswer((_) async => [rotation]);
    when(
      () => remote.claim(rotation.vaultId, rotation.id, any()),
    ).thenAnswer((_) async => claim);
    when(
      () => crypto.createPublicTrustAnchors(
        agentMessagePrivateKey: any(named: 'agentMessagePrivateKey'),
        manifestSigningPrivateKey: any(named: 'manifestSigningPrivateKey'),
        agentMessageKeyVersion: any(named: 'agentMessageKeyVersion'),
        manifestSigningKeyVersion: any(named: 'manifestSigningKeyVersion'),
      ),
    ).thenAnswer(
      (_) async => {
        'agentMessage': <String, Object>{'keyVersion': 1},
        'manifestSigning': <String, Object>{'keyVersion': 2},
      },
    );
    const recipient = RotationFullGrantRecipient(
      grantId: '55555555-5555-4555-8555-555555555555',
      agentId: '66666666-6666-4666-8666-666666666666',
      agentAccessEpoch: 3,
      recipientKeyVersion: 4,
      recipientKeyFingerprint: 'fingerprint',
      x25519PublicKey: 'public-key',
    );
    when(
      () =>
          remote.fullGrants(rotation.vaultId, rotation.id, any(), any(), any()),
    ).thenAnswer((_) async => const RotationPage(items: [recipient]));
    when(
      () => crypto.sealAgentVaultKey(
        recipient: recipient,
        organizationId: any(named: 'organizationId'),
        vaultId: rotation.vaultId,
        vaultKeyVersion: 1,
        vaultKey: any(named: 'vaultKey'),
        vaultSigningKeyVersion: 2,
        vaultSigningPrivateKey: any(named: 'vaultSigningPrivateKey'),
      ),
    ).thenAnswer((_) async => <String, Object?>{'grantId': recipient.grantId});

    await service.resumeAfterUnlock(
      memberId: '44444444-4444-4444-8444-444444444444',
      memberPrivateKey: Uint8List(32),
    );

    verify(
      () => crypto.sealAgentVaultKey(
        recipient: recipient,
        organizationId: '11111111-1111-4111-8111-111111111111',
        vaultId: rotation.vaultId,
        vaultKeyVersion: 1,
        vaultKey: any(named: 'vaultKey'),
        vaultSigningKeyVersion: 2,
        vaultSigningPrivateKey: any(named: 'vaultSigningPrivateKey'),
      ),
    ).called(1);
    final prepared = verify(
      () => remote.prepare(
        rotation.vaultId,
        rotation.id,
        any(),
        captureAny(),
        any(),
      ),
    ).captured.cast<Map<String, dynamic>>();
    expect(
      prepared,
      contains(
        predicate<Map<String, dynamic>>(
          (value) => value['agentWrappedVaultKeys'] is List,
        ),
      ),
    );
  });

  test(
    'pause cancels in-flight network work without persisting progress',
    () async {
      when(() => remote.listPending(any())).thenAnswer((invocation) async {
        final token = invocation.positionalArguments.single as CancelToken;
        await token.whenCancel;
        throw token.cancelError!;
      });

      final run = service.resumeAfterUnlock(
        memberId: '44444444-4444-4444-8444-444444444444',
        memberPrivateKey: Uint8List(32),
      );
      await Future<void>.delayed(Duration.zero);
      service.pause();

      await expectLater(
        run,
        throwsA(
          isA<DioException>().having(CancelToken.isCancel, 'cancel', true),
        ),
      );
      verifyNever(() => remote.prepare(any(), any(), any(), any(), any()));
    },
  );
}

VaultRotationModel _rotation({int targetGeneration = 2}) => VaultRotationModel(
  id: '22222222-2222-4222-8222-222222222221',
  vaultId: '22222222-2222-4222-8222-222222222222',
  status: 'Pending',
  scope: const ['Vdk'],
  baseMemberKeyGeneration: 1,
  targetMemberKeyGeneration: targetGeneration,
  baseKeyEpoch: const VaultKeyEpochModel(
    vaultKeyVersion: 1,
    vdkVersion: 1,
    agentMessageKeyVersion: 1,
    manifestSigningKeyVersion: 1,
  ),
  targetKeyEpoch: const VaultKeyEpochModel(
    vaultKeyVersion: 1,
    vdkVersion: 2,
    agentMessageKeyVersion: 1,
    manifestSigningKeyVersion: 1,
  ),
);

VaultRotationModel _manifestSigningRotation() => VaultRotationModel(
  id: '22222222-2222-4222-8222-222222222221',
  vaultId: '22222222-2222-4222-8222-222222222222',
  status: 'Pending',
  scope: const ['ManifestSigning'],
  baseMemberKeyGeneration: 1,
  targetMemberKeyGeneration: 1,
  baseKeyEpoch: const VaultKeyEpochModel(
    vaultKeyVersion: 1,
    vdkVersion: 1,
    agentMessageKeyVersion: 1,
    manifestSigningKeyVersion: 1,
  ),
  targetKeyEpoch: const VaultKeyEpochModel(
    vaultKeyVersion: 1,
    vdkVersion: 1,
    agentMessageKeyVersion: 1,
    manifestSigningKeyVersion: 2,
  ),
);

VaultRotationClaimModel _claim(VaultRotationModel rotation) =>
    VaultRotationClaimModel(
      rotation: rotation,
      fencingToken: '33333333-3333-4333-8333-333333333333',
      currentMemberVaultKey: const {
        'organizationId': '11111111-1111-4111-8111-111111111111',
      },
      currentDiscoveryKey: const {'ciphertext': 'current'},
      currentVaultPrivateKeys: const [
        {'privateKeyKind': 1},
        {'privateKeyKind': 2},
      ],
      pendingVaultPrivateKeys: const [],
      preparedMaterialReset: false,
    );
