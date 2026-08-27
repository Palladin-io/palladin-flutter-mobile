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
      () => crypto.openMemberVaultKey(
        any(),
        any(),
        expectedOrganizationId: any(named: 'expectedOrganizationId'),
        expectedVaultId: any(named: 'expectedVaultId'),
        expectedVaultKeyVersion: any(named: 'expectedVaultKeyVersion'),
        expectedMemberKeyGeneration: any(named: 'expectedMemberKeyGeneration'),
      ),
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
    verify(
      () => crypto.openMemberVaultKey(
        claim.currentMemberVaultKey,
        any(),
        expectedOrganizationId: '11111111-1111-4111-8111-111111111111',
        expectedVaultId: rotation.vaultId,
        expectedVaultKeyVersion: rotation.baseKeyEpoch.vaultKeyVersion,
        expectedMemberKeyGeneration: rotation.baseMemberKeyGeneration,
      ),
    ).called(1);
  });

  test(
    'binds a resumed pending Vault key to the target rotation epoch',
    () async {
      rotation = _rotation(scope: const []);
      final pending = _memberVaultKeyEnvelope();
      claim = _claim(rotation, pendingMemberVaultKey: pending);
      when(() => remote.listPending(any())).thenAnswer((_) async => [rotation]);
      when(
        () => remote.claim(rotation.vaultId, rotation.id, any()),
      ).thenAnswer((_) async => claim);

      await service.resumeAfterUnlock(
        memberId: '44444444-4444-4444-8444-444444444444',
        memberPrivateKey: Uint8List(32),
      );

      verify(
        () => crypto.openMemberVaultKey(
          pending,
          any(),
          expectedOrganizationId: '11111111-1111-4111-8111-111111111111',
          expectedVaultId: rotation.vaultId,
          expectedVaultKeyVersion: rotation.targetKeyEpoch.vaultKeyVersion,
          expectedMemberKeyGeneration: rotation.targetMemberKeyGeneration,
        ),
      ).called(1);
    },
  );

  test(
    'binds the current Vault key to the authoritative claim organization',
    () async {
      final wrongEnvelope = _memberVaultKeyEnvelope(
        organizationId: '99999999-9999-4999-8999-999999999999',
      );
      claim = _claim(rotation, currentMemberVaultKey: wrongEnvelope);
      when(
        () => remote.claim(rotation.vaultId, rotation.id, any()),
      ).thenAnswer((_) async => claim);
      when(
        () => crypto.openMemberVaultKey(
          wrongEnvelope,
          any(),
          expectedOrganizationId: '11111111-1111-4111-8111-111111111111',
          expectedVaultId: rotation.vaultId,
          expectedVaultKeyVersion: rotation.baseKeyEpoch.vaultKeyVersion,
          expectedMemberKeyGeneration: rotation.baseMemberKeyGeneration,
        ),
      ).thenThrow(const FormatException('organization mismatch'));

      await expectLater(
        service.resumeAfterUnlock(
          memberId: '44444444-4444-4444-8444-444444444444',
          memberPrivateKey: Uint8List(32),
        ),
        throwsFormatException,
      );

      verifyNever(() => crypto.generateKeys());
      verifyNever(() => remote.prepare(any(), any(), any(), any(), any()));
    },
  );

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

VaultRotationModel _rotation({
  int targetGeneration = 2,
  List<String> scope = const ['Vdk'],
}) => VaultRotationModel(
  id: '22222222-2222-4222-8222-222222222221',
  vaultId: '22222222-2222-4222-8222-222222222222',
  status: 'Pending',
  scope: scope,
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

VaultRotationClaimModel _claim(
  VaultRotationModel rotation, {
  Map<String, dynamic>? currentMemberVaultKey,
  Map<String, dynamic>? pendingMemberVaultKey,
}) => VaultRotationClaimModel(
  organizationId: '11111111-1111-4111-8111-111111111111',
  rotation: rotation,
  fencingToken: '33333333-3333-4333-8333-333333333333',
  currentMemberVaultKey: currentMemberVaultKey ?? _memberVaultKeyEnvelope(),
  currentDiscoveryKey: const {'ciphertext': 'current'},
  currentVaultPrivateKeys: const [
    {'privateKeyKind': 1},
    {'privateKeyKind': 2},
  ],
  pendingVaultPrivateKeys: const [],
  pendingMemberVaultKey: pendingMemberVaultKey,
  preparedMaterialReset: false,
);

Map<String, dynamic> _memberVaultKeyEnvelope({
  String organizationId = '11111111-1111-4111-8111-111111111111',
}) => {
  'wrappedVaultKey': {
    'descriptor': {
      'scope': {'organizationId': organizationId},
    },
  },
};
