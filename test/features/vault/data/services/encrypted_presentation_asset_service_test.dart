import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/encrypted_presentation_asset_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_bytes.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_aad.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_envelope_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;

class _Remote extends Mock implements VaultRemoteDatasource {}

class _Entries extends Mock implements EntryRemoteDatasource {}

class _Keys extends Mock implements VaultRotationCryptoService {}

class _Envelopes extends Mock implements VaultEnvelopeCryptography {}

const _organizationId = '00112233-4455-4677-8899-aabbccddeeff';
const _vaultId = '22222233-4455-4677-8899-aabbccddeeff';
const _entryId = '33333333-4455-4677-8899-aabbccddeeff';

Uint8List _png() =>
    Uint8List.fromList(image.encodePng(image.Image(width: 1, height: 1)));

Map<String, dynamic> _vault() => {
  'organizationId': _organizationId,
  'memberKeyGeneration': 3,
  'memberVaultKey': <String, dynamic>{},
  'memberVaultMetadata': {
    'metadataRevision': '8',
    'header': {'keyVersion': 4},
  },
};

void main() {
  late _Remote remote;
  late _Entries entries;
  late _Keys keys;
  late _Envelopes envelopes;
  late sodium_ffi.SodiumSumo sodium;

  setUpAll(() async {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(VaultAadProfile.entryKeyWrapper);
    registerFallbackValue(
      const VaultEnvelopeExpectations(
        aadContext: <String, dynamic>{},
        minimumMemberKeyGeneration: 0,
      ),
    );
    final library = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
    sodium = await sodium_ffi.SodiumSumoInit.init(
      () => DynamicLibrary.open(library ?? 'libsodium.so'),
    );
  });

  setUp(() {
    remote = _Remote();
    entries = _Entries();
    keys = _Keys();
    envelopes = _Envelopes();
    when(
      () => remote.getEncryptedVault(_vaultId),
    ).thenAnswer((_) async => _vault());
    when(
      () => keys.openMemberVaultKey(any(), any()),
    ).thenAnswer((_) async => Uint8List(32)..fillRange(0, 32, 7));
    when(
      () => remote.uploadEncryptedAsset(any(), any()),
    ).thenAnswer((_) async {});
  });

  EncryptedPresentationAssetService service() =>
      EncryptedPresentationAssetService(
        remote: remote,
        entries: entries,
        keys: keys,
        envelopes: envelopes,
        sodiumLoader: () async => sodium,
      );

  test('Vault and Entry use the same opaque authenticated pipeline', () async {
    final privateKey = Uint8List(32);
    final assets = service();
    final vaultReference = await assets.encryptAndUpload(
      target: PresentationAssetTarget.vault,
      vaultId: _vaultId,
      plaintext: _png(),
      memberPrivateKey: privateKey,
    );
    when(() => entries.getCanonicalEntry(_vaultId, _entryId)).thenAnswer(
      (_) async => {
        'currentRevision': '12',
        'entryKey': {'memberKeyGeneration': 3, 'keyVersion': 5},
      },
    );
    when(
      () => envelopes.decrypt(
        profile: any(named: 'profile'),
        envelope: any(named: 'envelope'),
        key: any(named: 'key'),
        expected: any(named: 'expected'),
      ),
    ).thenAnswer((_) async => Uint8List(32)..fillRange(0, 32, 9));
    final entryReference = await assets.encryptAndUpload(
      target: PresentationAssetTarget.entry,
      vaultId: _vaultId,
      entryId: _entryId,
      plaintext: _png(),
      memberPrivateKey: privateKey,
    );

    final payloads = verify(
      () => remote.uploadEncryptedAsset(_vaultId, captureAny()),
    ).captured.cast<Map<String, dynamic>>();
    expect(vaultReference, startsWith('asset:'));
    expect(entryReference, startsWith('asset:'));
    expect(payloads.map((value) => value['target']), [1, 2]);
    expect(
      payloads.every((value) => value.keys.contains('ciphertext')),
      isTrue,
    );
    expect(payloads.toString(), isNot(contains('uploadUrl')));

    final vaultPayload = payloads.first;
    final container = VaultProtocolBytes.base64UrlDecode(
      vaultPayload['ciphertext'] as String,
    );
    final assetId = vaultReference.split(':')[1];
    final metadata = EncryptedPresentationAssetMetadata(
      assetId: assetId,
      target: 1,
      entryId: null,
      mediaType: 'image/png',
      ciphertextLength: container.length,
      ciphertextSha256: vaultPayload['ciphertextSha256'] as String,
      downloadUrl: '/opaque/$assetId',
    );
    when(
      () => remote.getEncryptedAsset(_vaultId, assetId),
    ).thenAnswer((_) async => metadata);
    when(
      () => remote.downloadEncryptedAsset(metadata),
    ).thenAnswer((_) async => Uint8List.fromList(container));
    final opened = await assets.load(
      reference: vaultReference,
      target: PresentationAssetTarget.vault,
      vaultId: _vaultId,
      memberPrivateKey: privateKey,
    );
    expect(opened.bytes, _png());
    await expectLater(
      assets.load(
        reference: vaultReference,
        target: PresentationAssetTarget.entry,
        vaultId: _vaultId,
        entryId: _entryId,
        memberPrivateKey: privateKey,
      ),
      throwsA(
        isA<PresentationAssetException>().having(
          (error) => error.kind,
          'kind',
          PresentationAssetErrorKind.scope,
        ),
      ),
    );
    assets.lock();
    expect(opened.bytes.every((value) => value == 0), isTrue);
  });

  test('rejects malformed and polyglot image bytes before network', () async {
    final polyglot = Uint8List.fromList([..._png(), 1]);
    for (final bytes in [
      Uint8List.fromList([1, 2, 3]),
      polyglot,
    ]) {
      await expectLater(
        service().encryptAndUpload(
          target: PresentationAssetTarget.vault,
          vaultId: _vaultId,
          plaintext: bytes,
          memberPrivateKey: Uint8List(32),
        ),
        throwsA(isA<PresentationAssetException>()),
      );
    }
    verifyNever(() => remote.uploadEncryptedAsset(any(), any()));
  });

  test(
    'rejects oversized plaintext before any key or network operation',
    () async {
      await expectLater(
        service().encryptAndUpload(
          target: PresentationAssetTarget.vault,
          vaultId: _vaultId,
          plaintext: Uint8List(
            EncryptedPresentationAssetService.maximumPlaintextBytes + 1,
          ),
          memberPrivateKey: Uint8List(32),
        ),
        throwsA(
          isA<PresentationAssetException>().having(
            (error) => error.kind,
            'kind',
            PresentationAssetErrorKind.tooLarge,
          ),
        ),
      );
      verifyNever(() => remote.getEncryptedVault(any()));
    },
  );
}
