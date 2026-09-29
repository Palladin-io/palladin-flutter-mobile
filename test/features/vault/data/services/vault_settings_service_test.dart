import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/encrypted_presentation_asset_service.dart';
import 'package:mobile_palladin/core/crypto/vault_session_store.dart';
import 'package:mobile_palladin/features/vault/data/models/vault_v2_contracts.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_settings_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_plaintext.dart';

class _Remote extends Mock implements VaultRemoteDatasource {}

class _VaultCrypto extends Mock implements VaultCryptoService {}

class _Assets extends Mock implements EncryptedPresentationAssetService {}

const vaultId = '22222233-4455-4677-8899-aabbccddeeff';
const organizationId = '00112233-4455-4677-8899-aabbccddeeff';

VaultEntity _expected({String description = 'Current'}) => VaultEntity(
  id: vaultId,
  name: 'Production',
  description: description,
  icon: 'shield',
  color: '#EB4747',
  grantMode: GrantMode.granular,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  entryCount: 2,
  activeGrantCount: 1,
  memberCount: 2,
);

Map<String, dynamic> _fresh({Map<String, dynamic>? metadata}) => {
  'id': vaultId,
  'organizationId': organizationId,
  'memberKeyGeneration': 3,
  'currentKeyEpoch': {'vaultKeyVersion': 7},
  'memberVaultKey': <String, dynamic>{},
  'memberVaultMetadata':
      metadata ??
      {
        'descriptor': {
          'protocolVersion': 2,
          'cryptoSuiteId': 'palladin-vault-xchacha-v1',
          'purpose': 1,
          'scope': {'organizationId': organizationId, 'vaultId': vaultId},
          'resourceRevision': '12',
          'keyVersion': 7,
          'memberKeyGeneration': 3,
          'binding': <String, dynamic>{},
        },
        'encodedSuitePayload': 'opaque-old',
      },
};

void main() {
  late _Remote remote;
  late _VaultCrypto vaultCrypto;
  late _Assets assets;
  late VaultSettingsService service;
  late MemberVaultMetadata sealedMetadata;

  setUpAll(() {
    registerFallbackValue(File('unused'));
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(PresentationAssetMediaType.png);
    registerFallbackValue(
      const MemberVaultMetadata(
        name: 'fallback',
        description: null,
        icon: null,
        color: null,
        grantMode: 'granular',
      ),
    );
  });

  setUp(() {
    remote = _Remote();
    vaultCrypto = _VaultCrypto();
    assets = _Assets();
    sealedMetadata = const MemberVaultMetadata(
      name: 'unset',
      description: null,
      icon: null,
      color: null,
      grantMode: 'granular',
    );
    service = VaultSettingsService(
      remote: remote,
      vaultCrypto: vaultCrypto,
      assets: assets,
    );
    when(
      () => remote.getEncryptedVault(vaultId),
    ).thenAnswer((_) async => _fresh());
    when(
      () => vaultCrypto.openVaultProjection(
        json: any(named: 'json'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer(
      (_) async => OpenedVaultProjection(
        organizationId: organizationId,
        vaultId: vaultId,
        vaultKey: Uint8List(32)..fillRange(0, 32, 9),
        vaultDiscoveryKey: null,
        metadata: const MemberVaultMetadata(
          name: 'Production',
          description: 'Current',
          icon: GlyphVaultIcon('shield'),
          color: '#EB4747',
          grantMode: 'granular',
        ),
        epoch: const VaultKeyEpochModel(
          vaultKeyVersion: 7,
          vdkVersion: 1,
          agentMessageKeyVersion: 1,
          manifestSigningKeyVersion: 1,
        ),
        memberKeyGeneration: 3,
        wrapper: const MemberVaultKeyWrapperMetadata(
          wrapperSuiteId: 'x25519',
          wrappedKeyVersion: 7,
          memberKeyGeneration: 3,
          recipientKeyVersion: 1,
          recipientFingerprint: 'fingerprint',
        ),
      ),
    );
    when(
      () => vaultCrypto.sealMemberVaultMetadata(
        currentEnvelope: any(named: 'currentEnvelope'),
        metadata: any(named: 'metadata'),
        vaultKey: any(named: 'vaultKey'),
        organizationId: any(named: 'organizationId'),
        vaultId: any(named: 'vaultId'),
        memberKeyGeneration: any(named: 'memberKeyGeneration'),
      ),
    ).thenAnswer((invocation) async {
      sealedMetadata =
          invocation.namedArguments[#metadata] as MemberVaultMetadata;
      return {
        'descriptor': {
          ...(_fresh()['memberVaultMetadata']['descriptor'] as Map),
          'resourceRevision': '13',
        },
        'encodedSuitePayload': 'opaque-new',
      };
    });
    when(() => remote.replaceEncryptedMetadata(vaultId, any())).thenAnswer(
      (_) async => Response<void>(
        requestOptions: RequestOptions(path: '/api/vaults/$vaultId'),
        statusCode: 204,
      ),
    );
  });

  test(
    'stores the uploaded asset UUID in canonical encrypted metadata',
    () async {
      const assetId = '12345678-1234-4234-9234-123456789abc';
      when(
        () => assets.uploadFile(
          target: PresentationAssetTarget.vault,
          vaultId: vaultId,
          file: any(named: 'file'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async => 'asset:$assetId');
      final result = await service.update(
        expected: _expected(),
        name: 'Production',
        description: 'Current',
        icon: 'shield',
        color: '#EB4747',
        memberPrivateKey: Uint8List(32),
        localIconPath: '/synthetic/icon.png',
      );
      expect(
        sealedMetadata.icon,
        isA<EncryptedAssetVaultIcon>().having(
          (icon) => icon.assetId,
          'assetId',
          assetId,
        ),
      );
      expect(result.icon, 'asset:$assetId');
      verifyNever(() => assets.delete(any(), any()));
    },
  );

  test('fails before write when authenticated base differs', () async {
    await expectLater(
      service.update(
        expected: _expected(description: 'Stale'),
        name: 'Next',
        description: 'Current',
        icon: 'shield',
        color: '#EB4747',
        memberPrivateKey: Uint8List(32),
      ),
      throwsA(
        isA<VaultSettingsException>().having(
          (error) => error.kind,
          'kind',
          VaultSettingsErrorKind.conflict,
        ),
      ),
    );

    verifyNever(() => remote.replaceEncryptedMetadata(vaultId, any()));
  });

  test('sends only revisioned encrypted metadata to backend', () async {
    final updated = await service.update(
      expected: _expected(),
      name: 'Production 2',
      description: 'Current',
      icon: 'shield',
      color: '#EB4747',
      memberPrivateKey: Uint8List(32),
    );

    final captured =
        verify(
              () => remote.replaceEncryptedMetadata(vaultId, captureAny()),
            ).captured.single
            as Map<String, dynamic>;
    expect((captured['descriptor'] as Map)['resourceRevision'], '13');
    expect(captured['encodedSuitePayload'], 'opaque-new');
    expect(captured.toString(), isNot(contains('Production 2')));
    expect(sealedMetadata.name, 'Production 2');
    expect(sealedMetadata.grantMode, 'granular');
    expect(sealedMetadata.icon, isA<GlyphVaultIcon>());
    expect(updated.name, 'Production 2');
  });

  test('explicit conflict never reports the edit as committed', () async {
    when(() => remote.replaceEncryptedMetadata(vaultId, any())).thenAnswer(
      (_) async => Response<void>(
        requestOptions: RequestOptions(path: '/api/vaults/$vaultId'),
        statusCode: 409,
      ),
    );

    await expectLater(
      service.update(
        expected: _expected(),
        name: 'Next',
        description: 'Current',
        icon: 'shield',
        color: '#EB4747',
        memberPrivateKey: Uint8List(32),
      ),
      throwsA(
        isA<VaultSettingsException>().having(
          (error) => error.kind,
          'kind',
          VaultSettingsErrorKind.conflict,
        ),
      ),
    );
  });

  test(
    'explicit conflict compensates a newly uploaded encrypted asset',
    () async {
      final icon = File(
        '${Directory.systemTemp.path}/palladin-vault-settings-${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await icon.writeAsBytes(const [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
        0,
        0,
        0,
        13,
        73,
        72,
        68,
        82,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
      ]);
      addTearDown(() async {
        if (await icon.exists()) await icon.delete();
      });
      const assetId = '12345678-1234-4234-9234-123456789abc';
      when(
        () => assets.uploadFile(
          target: PresentationAssetTarget.vault,
          vaultId: any(named: 'vaultId'),
          file: any(named: 'file'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async => 'asset:$assetId');
      when(() => assets.delete(vaultId, assetId)).thenAnswer((_) async {});
      when(() => remote.replaceEncryptedMetadata(vaultId, any())).thenAnswer(
        (_) async => Response<void>(
          requestOptions: RequestOptions(path: '/api/vaults/$vaultId'),
          statusCode: 409,
        ),
      );

      await expectLater(
        service.update(
          expected: _expected(),
          name: 'Next',
          description: 'Current',
          icon: 'shield',
          color: '#EB4747',
          memberPrivateKey: Uint8List(32),
          localIconPath: icon.path,
        ),
        throwsA(
          isA<VaultSettingsException>().having(
            (error) => error.kind,
            'kind',
            VaultSettingsErrorKind.conflict,
          ),
        ),
      );

      verify(() => assets.delete(vaultId, assetId)).called(1);
    },
  );
}
