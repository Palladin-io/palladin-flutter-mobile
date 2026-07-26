import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/encrypted_presentation_asset_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_bytes.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;

class _Remote extends Mock implements VaultRemoteDatasource {}

void main() {
  test('uploads only a bounded authenticated PLDNV2AS container', () async {
    final library = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
    final sodium = await sodium_ffi.SodiumSumoInit.init(
      () => DynamicLibrary.open(library ?? 'libsodium.so'),
    );
    final remote = _Remote();
    when(
      () => remote.uploadEncryptedAsset(any(), any()),
    ).thenAnswer((_) async {});
    final service = EncryptedPresentationAssetService(
      remote: remote,
      sodiumLoader: () async => sodium,
    );
    final plaintext = Uint8List.fromList([
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

    final reference = await service.encryptAndUpload(
      organizationId: '00112233-4455-4677-8899-aabbccddeeff',
      vaultId: '22222233-4455-4677-8899-aabbccddeeff',
      vaultKey: Uint8List(32)..fillRange(0, 32, 7),
      plaintext: plaintext,
      mediaType: PresentationAssetMediaType.png,
      keyVersion: 4,
      memberKeyGeneration: 3,
    );

    final captured =
        verify(
              () => remote.uploadEncryptedAsset(any(), captureAny()),
            ).captured.single
            as Map<String, dynamic>;
    final container = VaultProtocolBytes.base64UrlDecode(
      captured['ciphertext'] as String,
    );
    expect(String.fromCharCodes(container.sublist(0, 8)), 'PLDNV2AS');
    expect(captured['mediaType'], 'image/png');
    expect(captured.toString(), isNot(contains(plaintext.toString())));
    expect(reference, startsWith('asset:'));
  });

  test('rejects corrupt image bytes before any network request', () async {
    final remote = _Remote();
    final service = EncryptedPresentationAssetService(remote: remote);

    await expectLater(
      service.encryptAndUpload(
        organizationId: '00112233-4455-4677-8899-aabbccddeeff',
        vaultId: '22222233-4455-4677-8899-aabbccddeeff',
        vaultKey: Uint8List(32),
        plaintext: Uint8List.fromList([1, 2, 3]),
        mediaType: PresentationAssetMediaType.png,
        keyVersion: 1,
        memberKeyGeneration: 1,
      ),
      throwsFormatException,
    );
    verifyNever(() => remote.uploadEncryptedAsset(any(), any()));
  });
}
