import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/encrypted_presentation_asset_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_envelope_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_aad.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_settings_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';

class _Remote extends Mock implements VaultRemoteDatasource {}

class _Keys extends Mock implements VaultRotationCryptoService {}

class _Envelopes extends Mock implements VaultEnvelopeCryptography {}

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
        'organizationId': organizationId,
        'vaultId': vaultId,
        'metadataRevision': '12',
        'header': {
          'protocolVersion': 2,
          'algorithmSuite': 1,
          'resourceKind': 1,
          'projectionKind': 1,
          'resourceRevision': '12',
          'keyVersion': 7,
          'memberKeyGeneration': 3,
          'nonce': 'old',
        },
        'ciphertext': 'opaque-old',
      },
};

void main() {
  late _Remote remote;
  late _Keys keys;
  late _Envelopes envelopes;
  late _Assets assets;
  late VaultSettingsService service;

  setUpAll(() {
    registerFallbackValue(File('unused'));
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(VaultAadProfile.memberVaultMetadata);
    registerFallbackValue(PresentationAssetMediaType.png);
    registerFallbackValue(
      const VaultEnvelopeExpectations(
        aadContext: {},
        minimumMemberKeyGeneration: 0,
      ),
    );
  });

  setUp(() {
    remote = _Remote();
    keys = _Keys();
    envelopes = _Envelopes();
    assets = _Assets();
    service = VaultSettingsService(
      remote: remote,
      keys: keys,
      envelopes: envelopes,
      assets: assets,
    );
    when(
      () => remote.getEncryptedVault(vaultId),
    ).thenAnswer((_) async => _fresh());
    when(
      () => keys.openMemberVaultKey(any(), any()),
    ).thenAnswer((_) async => Uint8List(32)..fillRange(0, 32, 9));
    when(
      () => envelopes.decrypt(
        profile: any(named: 'profile'),
        envelope: any(named: 'envelope'),
        key: any(named: 'key'),
        expected: any(named: 'expected'),
      ),
    ).thenAnswer(
      (_) async => Uint8List.fromList(
        utf8.encode(
          '{"color":"#EB4747","description":"Current","iconReference":"shield","name":"Production"}',
        ),
      ),
    );
    when(
      () => envelopes.encrypt(
        profile: any(named: 'profile'),
        context: any(named: 'context'),
        plaintext: any(named: 'plaintext'),
        key: any(named: 'key'),
      ),
    ).thenAnswer(
      (_) async => {'nonce': 'fresh-nonce', 'ciphertext': 'opaque-new'},
    );
    when(() => remote.replaceEncryptedMetadata(vaultId, any())).thenAnswer(
      (_) async => Response<void>(
        requestOptions: RequestOptions(path: '/api/vaults/$vaultId'),
        statusCode: 204,
      ),
    );
  });

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
    expect(captured['metadataRevision'], '13');
    expect(captured['ciphertext'], 'opaque-new');
    expect(captured.toString(), isNot(contains('Production 2')));
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
      ).thenAnswer((_) async => 'asset:$assetId:8');
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
