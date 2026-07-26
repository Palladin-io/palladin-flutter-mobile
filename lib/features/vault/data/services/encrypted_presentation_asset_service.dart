import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../core/crypto/sodium_provider.dart';
import '../datasources/vault_remote_datasource.dart';
import 'vault_protocol/vault_protocol_bytes.dart';
import 'vault_protocol/vault_protocol_kdf.dart';

enum PresentationAssetMediaType {
  jpeg('image/jpeg', 1),
  png('image/png', 2),
  webp('image/webp', 3);

  const PresentationAssetMediaType(this.wire, this.id);
  final String wire;
  final int id;
}

/// Encrypts bounded icons into the frozen `PLDNV2AS` binary container.
class EncryptedPresentationAssetService {
  EncryptedPresentationAssetService({
    required VaultRemoteDatasource remote,
    Future<SodiumSumo> Function()? sodiumLoader,
  }) : _remote = remote,
       _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  static const maximumPlaintextBytes = 2 * 1024 * 1024;
  final VaultRemoteDatasource _remote;
  final Future<SodiumSumo> Function() _sodiumLoader;

  Future<String> encryptAndUpload({
    required String organizationId,
    required String vaultId,
    required Uint8List vaultKey,
    required Uint8List plaintext,
    required PresentationAssetMediaType mediaType,
    required int keyVersion,
    required int memberKeyGeneration,
  }) async {
    _validate(plaintext, mediaType);
    final assetId = _uuidV4();
    final key = deriveVaultProjectionKey(
      vaultKey,
      VaultKdfContext(
        purpose: VaultKdfPurpose.encryptedAsset,
        resourceKind: 1,
        organizationId: organizationId,
        vaultId: vaultId,
        keyVersion: keyVersion,
        memberKeyGeneration: memberKeyGeneration,
      ),
    );
    final sodium = await _sodiumLoader();
    final nonce = sodium.randombytes.buf(
      sodium.crypto.aeadXChaCha20Poly1305IETF.nonceBytes,
    );
    final aad = _aad(
      organizationId,
      vaultId,
      assetId,
      mediaType,
      keyVersion,
      memberKeyGeneration,
    );
    final secureKey = SecureKey.fromList(sodium, key);
    Uint8List? container;
    try {
      final ciphertext = sodium.crypto.aeadXChaCha20Poly1305IETF.encrypt(
        message: plaintext,
        nonce: nonce,
        key: secureKey,
        additionalData: aad,
      );
      container = VaultProtocolBytes.concat([
        _header(assetId, mediaType, keyVersion, memberKeyGeneration, nonce),
        ciphertext,
      ]);
      final digest = Uint8List.fromList(sha256.convert(container).bytes);
      await _remote.uploadEncryptedAsset(vaultId, {
        'vaultId': vaultId,
        'assetId': assetId,
        'target': 1,
        'entryId': null,
        'mediaType': mediaType.wire,
        'ciphertext': VaultProtocolBytes.base64UrlEncode(container),
        'ciphertextSha256': VaultProtocolBytes.base64UrlEncode(digest),
      });
      digest.fillRange(0, digest.length, 0);
      return 'asset:$assetId';
    } finally {
      secureKey.dispose();
      key.fillRange(0, key.length, 0);
      nonce.fillRange(0, nonce.length, 0);
      aad.fillRange(0, aad.length, 0);
      container?.fillRange(0, container.length, 0);
    }
  }

  Future<void> delete(String vaultId, String assetId) =>
      _remote.deleteEncryptedAsset(vaultId, assetId);

  Uint8List _header(
    String assetId,
    PresentationAssetMediaType mediaType,
    int keyVersion,
    int generation,
    Uint8List nonce,
  ) => VaultProtocolBytes.concat([
    VaultProtocolBytes.utf8Encode('PLDNV2AS'),
    VaultProtocolBytes.u16(1),
    VaultProtocolBytes.u16(2),
    VaultProtocolBytes.u16(1),
    VaultProtocolBytes.u16(1),
    VaultProtocolBytes.u16(mediaType.id),
    VaultProtocolBytes.u16(0),
    VaultProtocolBytes.u32(keyVersion),
    VaultProtocolBytes.u32(generation),
    VaultProtocolBytes.uuid(assetId),
    Uint8List(16),
    nonce,
  ]);

  Uint8List _aad(
    String organizationId,
    String vaultId,
    String assetId,
    PresentationAssetMediaType mediaType,
    int keyVersion,
    int generation,
  ) => VaultProtocolBytes.concat([
    VaultProtocolBytes.utf8Encode('PLDNV2AA'),
    VaultProtocolBytes.u16(1),
    VaultProtocolBytes.uuid(organizationId),
    VaultProtocolBytes.uuid(vaultId),
    VaultProtocolBytes.uuid(assetId),
    VaultProtocolBytes.u16(1),
    Uint8List(16),
    VaultProtocolBytes.u16(mediaType.id),
    VaultProtocolBytes.u32(keyVersion),
    VaultProtocolBytes.u32(generation),
  ]);

  void _validate(Uint8List bytes, PresentationAssetMediaType mediaType) {
    if (bytes.isEmpty || bytes.length > maximumPlaintextBytes) {
      throw const FormatException('Icon exceeds size limit');
    }
    final valid = switch (mediaType) {
      PresentationAssetMediaType.png =>
        bytes.length >= 24 &&
            VaultProtocolBytes.constantTimeEquals(
              Uint8List.sublistView(bytes, 0, 8),
              Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
            ),
      PresentationAssetMediaType.jpeg =>
        bytes.length >= 4 &&
            bytes[0] == 0xff &&
            bytes[1] == 0xd8 &&
            bytes[bytes.length - 2] == 0xff &&
            bytes.last == 0xd9,
      PresentationAssetMediaType.webp =>
        bytes.length >= 30 &&
            String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
            String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP',
    };
    if (!valid) throw const FormatException('Icon content type mismatch');
  }

  String _uuidV4() {
    final bytes = Uint8List.fromList(
      List.generate(16, (_) => Random.secure().nextInt(256)),
    );
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = VaultProtocolBytes.hexEncode(bytes);
    bytes.fillRange(0, bytes.length, 0);
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
