import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;
import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../core/crypto/sodium_provider.dart';
import '../datasources/entry_remote_datasource.dart';
import '../datasources/vault_remote_datasource.dart';
import 'entry_v2_crypto_service.dart';
import 'vault_protocol/vault_protocol_bytes.dart';
import 'vault_protocol/vault_protocol_kdf.dart';
import 'vault_rotation_crypto_service.dart';

enum PresentationAssetTarget {
  vault(1),
  entry(2);

  const PresentationAssetTarget(this.id);
  final int id;
}

enum PresentationAssetMediaType {
  jpeg('image/jpeg', 1),
  png('image/png', 2),
  webp('image/webp', 3);

  const PresentationAssetMediaType(this.wire, this.id);
  final String wire;
  final int id;
}

enum PresentationAssetErrorKind {
  unsupportedFormat,
  tooLarge,
  dimensions,
  corrupt,
  scope,
  network,
}

final class PresentationAssetException implements Exception {
  const PresentationAssetException(this.kind);
  final PresentationAssetErrorKind kind;
}

final class PresentationAssetValue {
  const PresentationAssetValue(this.bytes, this.mediaType);
  final Uint8List bytes;
  final PresentationAssetMediaType mediaType;
  void clear() => bytes.fillRange(0, bytes.length, 0);
}

/// One zero-knowledge pipeline for Vault and Entry presentation assets.
class EncryptedPresentationAssetService {
  EncryptedPresentationAssetService({
    required VaultRemoteDatasource remote,
    required EntryRemoteDatasource entries,
    required VaultRotationCryptoService keys,
    required EntryV2CryptoService entryCrypto,
    Future<SodiumSumo> Function()? sodiumLoader,
  }) : _remote = remote,
       _entries = entries,
       _keys = keys,
       _entryCrypto = entryCrypto,
       _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  static const maximumPlaintextBytes = 2 * 1024 * 1024;
  static const maximumCiphertextBytes = 5 * 1024 * 1024;
  static const maximumDimension = 2048;
  static const maximumPixels = 4 * 1024 * 1024;
  static const _magic = 'PLDNV2AS';
  final VaultRemoteDatasource _remote;
  final EntryRemoteDatasource _entries;
  final VaultRotationCryptoService _keys;
  final EntryV2CryptoService _entryCrypto;
  final Future<SodiumSumo> Function() _sodiumLoader;
  final Set<PresentationAssetValue> _liveValues = {};

  /// Releases an owned decoded byte buffer as soon as its widget is disposed.
  void release(PresentationAssetValue value) {
    _liveValues.remove(value);
    value.clear();
  }

  /// Clears every currently owned decoded buffer when the app locks.
  void lock() {
    for (final value in _liveValues) {
      value.clear();
    }
    _liveValues.clear();
  }

  Future<String> uploadFile({
    required PresentationAssetTarget target,
    required String vaultId,
    String? entryId,
    required File file,
    required Uint8List memberPrivateKey,
  }) async {
    final length = await file.length();
    if (length < 1 || length > maximumPlaintextBytes) {
      throw const PresentationAssetException(
        PresentationAssetErrorKind.tooLarge,
      );
    }
    final bytes = await file.readAsBytes();
    try {
      return await encryptAndUpload(
        target: target,
        vaultId: vaultId,
        entryId: entryId,
        plaintext: bytes,
        memberPrivateKey: memberPrivateKey,
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<String> encryptAndUpload({
    required PresentationAssetTarget target,
    required String vaultId,
    String? entryId,
    required Uint8List plaintext,
    required Uint8List memberPrivateKey,
  }) async {
    final mediaType = _inspect(plaintext);
    final context = await _context(target, vaultId, entryId, memberPrivateKey);
    Uint8List? assetKey, nonce, aad, container, digest;
    SecureKey? secureKey;
    try {
      final assetId = _uuidV4();
      assetKey = deriveVaultProjectionKey(
        context.baseKey,
        VaultKdfContext(
          purpose: VaultKdfPurpose.encryptedAsset,
          resourceKind: target.id,
          organizationId: context.organizationId,
          vaultId: vaultId,
          entryId: entryId,
          keyVersion: context.keyVersion,
          memberKeyGeneration: context.generation,
        ),
      );
      final sodium = await _sodiumLoader();
      nonce = sodium.randombytes.buf(
        sodium.crypto.aeadXChaCha20Poly1305IETF.nonceBytes,
      );
      aad = _aad(
        context.organizationId,
        vaultId,
        assetId,
        target,
        entryId,
        mediaType,
        context.keyVersion,
        context.generation,
      );
      secureKey = SecureKey.fromList(sodium, assetKey);
      final ciphertext = sodium.crypto.aeadXChaCha20Poly1305IETF.encrypt(
        message: plaintext,
        nonce: nonce,
        key: secureKey,
        additionalData: aad,
      );
      container = VaultProtocolBytes.concat([
        VaultProtocolBytes.utf8Encode(_magic),
        VaultProtocolBytes.u16(1),
        VaultProtocolBytes.u16(2),
        VaultProtocolBytes.u16(1),
        VaultProtocolBytes.u16(target.id),
        VaultProtocolBytes.u16(mediaType.id),
        VaultProtocolBytes.u16(0),
        VaultProtocolBytes.u32(context.keyVersion),
        VaultProtocolBytes.u32(context.generation),
        VaultProtocolBytes.uuid(assetId),
        entryId == null ? Uint8List(16) : VaultProtocolBytes.uuid(entryId),
        nonce,
        ciphertext,
      ]);
      if (container.length > maximumCiphertextBytes) {
        throw const PresentationAssetException(
          PresentationAssetErrorKind.tooLarge,
        );
      }
      digest = Uint8List.fromList(sha256.convert(container).bytes);
      await _remote.uploadEncryptedAsset(vaultId, {
        'vaultId': vaultId,
        'assetId': assetId,
        'target': target.id,
        'entryId': entryId,
        'mediaType': mediaType.wire,
        'ciphertext': VaultProtocolBytes.base64UrlEncode(container),
        'ciphertextSha256': VaultProtocolBytes.base64UrlEncode(digest),
      });
      return 'asset:$assetId';
    } on PresentationAssetException {
      rethrow;
    } on FormatException {
      throw const PresentationAssetException(
        PresentationAssetErrorKind.corrupt,
      );
    } catch (_) {
      throw const PresentationAssetException(
        PresentationAssetErrorKind.network,
      );
    } finally {
      secureKey?.dispose();
      context.clear();
      assetKey?.fillRange(0, assetKey.length, 0);
      nonce?.fillRange(0, nonce.length, 0);
      aad?.fillRange(0, aad.length, 0);
      container?.fillRange(0, container.length, 0);
      digest?.fillRange(0, digest.length, 0);
    }
  }

  Future<PresentationAssetValue> load({
    required String reference,
    required PresentationAssetTarget target,
    required String vaultId,
    String? entryId,
    required Uint8List memberPrivateKey,
  }) async {
    final parts = reference.split(':');
    if (parts.length != 2 || parts[0] != 'asset') {
      throw const PresentationAssetException(PresentationAssetErrorKind.scope);
    }
    final assetId = parts[1];
    VaultProtocolBytes.uuid(assetId);
    Uint8List? container;
    Uint8List? digest;
    Uint8List? plaintext;
    _AssetContext? context;
    try {
      final metadata = await _remote.getEncryptedAsset(vaultId, assetId);
      if (metadata.assetId != assetId ||
          metadata.target != target.id ||
          metadata.entryId != entryId ||
          metadata.ciphertextLength < 1 ||
          metadata.ciphertextLength > maximumCiphertextBytes) {
        throw const PresentationAssetException(
          PresentationAssetErrorKind.scope,
        );
      }
      container = await _remote.downloadEncryptedAsset(metadata);
      if (container.length != metadata.ciphertextLength) {
        throw const PresentationAssetException(
          PresentationAssetErrorKind.corrupt,
        );
      }
      digest = Uint8List.fromList(sha256.convert(container).bytes);
      final expectedDigest = VaultProtocolBytes.base64UrlDecode(
        metadata.ciphertextSha256,
      );
      final digestMatches = VaultProtocolBytes.constantTimeEquals(
        digest,
        expectedDigest,
      );
      expectedDigest.fillRange(0, expectedDigest.length, 0);
      if (!digestMatches) {
        throw const PresentationAssetException(
          PresentationAssetErrorKind.corrupt,
        );
      }
      final parsed = _parse(
        container,
        assetId,
        target,
        entryId,
        metadata.mediaType,
      );
      context = await _context(target, vaultId, entryId, memberPrivateKey);
      if (parsed.keyVersion != context.keyVersion ||
          parsed.generation != context.generation) {
        throw const PresentationAssetException(
          PresentationAssetErrorKind.scope,
        );
      }
      final key = deriveVaultProjectionKey(
        context.baseKey,
        VaultKdfContext(
          purpose: VaultKdfPurpose.encryptedAsset,
          resourceKind: target.id,
          organizationId: context.organizationId,
          vaultId: vaultId,
          entryId: entryId,
          keyVersion: parsed.keyVersion,
          memberKeyGeneration: parsed.generation,
        ),
      );
      SecureKey? secureKey;
      Uint8List? aad;
      try {
        final sodium = await _sodiumLoader();
        secureKey = SecureKey.fromList(sodium, key);
        aad = _aad(
          context.organizationId,
          vaultId,
          assetId,
          target,
          entryId,
          parsed.mediaType,
          parsed.keyVersion,
          parsed.generation,
        );
        plaintext = sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
          cipherText: parsed.ciphertext,
          nonce: parsed.nonce,
          key: secureKey,
          additionalData: aad,
        );
      } catch (_) {
        throw const PresentationAssetException(
          PresentationAssetErrorKind.corrupt,
        );
      } finally {
        secureKey?.dispose();
        key.fillRange(0, key.length, 0);
        aad?.fillRange(0, aad.length, 0);
      }
      if (_inspect(plaintext) != parsed.mediaType) {
        throw const PresentationAssetException(
          PresentationAssetErrorKind.corrupt,
        );
      }
      final result = PresentationAssetValue(plaintext, parsed.mediaType);
      _liveValues.add(result);
      plaintext = null;
      return result;
    } on PresentationAssetException {
      rethrow;
    } on FormatException {
      throw const PresentationAssetException(
        PresentationAssetErrorKind.corrupt,
      );
    } catch (_) {
      throw const PresentationAssetException(
        PresentationAssetErrorKind.network,
      );
    } finally {
      context?.clear();
      container?.fillRange(0, container.length, 0);
      digest?.fillRange(0, digest.length, 0);
      plaintext?.fillRange(0, plaintext.length, 0);
    }
  }

  Future<void> delete(String vaultId, String reference) {
    final parts = reference.split(':');
    final assetId = parts.length >= 2 ? parts[1] : reference;
    return _remote.deleteEncryptedAsset(vaultId, assetId);
  }

  Future<_AssetContext> _context(
    PresentationAssetTarget target,
    String vaultId,
    String? entryId,
    Uint8List privateKey,
  ) async {
    if (privateKey.length != 32 ||
        (target == PresentationAssetTarget.entry) != (entryId != null)) {
      throw const PresentationAssetException(PresentationAssetErrorKind.scope);
    }
    final vault = await _remote.getEncryptedVault(vaultId);
    final organizationId = vault['organizationId'] as String;
    final generation = vault['memberKeyGeneration'] as int;
    final vaultKeyVersion =
        (vault['currentKeyEpoch'] as Map)['vaultKeyVersion'] as int;
    final vaultKey = await _keys.openMemberVaultKey(
      Map<String, dynamic>.from(vault['memberVaultKey'] as Map),
      privateKey,
      expectedOrganizationId: organizationId,
      expectedVaultId: vaultId,
      expectedVaultKeyVersion: vaultKeyVersion,
      expectedMemberKeyGeneration: generation,
    );
    if (target == PresentationAssetTarget.vault) {
      return _AssetContext(
        organizationId,
        vaultKeyVersion,
        generation,
        vaultKey,
      );
    }
    try {
      final entry = await _entries.getCanonicalEntry(vaultId, entryId!);
      final keyVersion = entry['currentKeyVersion'] as int;
      final wrapper = Map<String, dynamic>.from(entry['entryKey'] as Map);
      final descriptor = wrapper['descriptor'] as Map;
      final scope = descriptor['scope'] as Map;
      final binding = descriptor['binding'] as Map;
      final wrapperGeneration = descriptor['memberKeyGeneration'] as int;
      // Authenticate the wrapper against the requested resource and REST heads,
      // never against scope/version values copied from the wrapper itself.
      if (scope['organizationId'] != organizationId ||
          scope['vaultId'] != vaultId ||
          scope['entryId'] != entryId ||
          descriptor['keyVersion'] != keyVersion ||
          wrapperGeneration > generation ||
          binding['wrappingVaultKeyVersion'] != vaultKeyVersion) {
        throw const PresentationAssetException(
          PresentationAssetErrorKind.scope,
        );
      }
      final entryDek = await _entryCrypto.openEntryDek(
        entryKey: wrapper,
        vaultKey: vaultKey,
      );
      return _AssetContext(organizationId, keyVersion, generation, entryDek);
    } finally {
      vaultKey.fillRange(0, vaultKey.length, 0);
    }
  }

  PresentationAssetMediaType _inspect(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maximumPlaintextBytes) {
      throw const PresentationAssetException(
        PresentationAssetErrorKind.tooLarge,
      );
    }
    final type =
        bytes.length >= 24 && _prefix(bytes, [137, 80, 78, 71, 13, 10, 26, 10])
        ? PresentationAssetMediaType.png
        : bytes.length >= 4 &&
              bytes[0] == 0xff &&
              bytes[1] == 0xd8 &&
              bytes[bytes.length - 2] == 0xff &&
              bytes.last == 0xd9
        ? PresentationAssetMediaType.jpeg
        : bytes.length >= 30 &&
              ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
              ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP'
        ? PresentationAssetMediaType.webp
        : throw const PresentationAssetException(
            PresentationAssetErrorKind.unsupportedFormat,
          );
    if (type == PresentationAssetMediaType.png && !_pngEndsExactly(bytes) ||
        type == PresentationAssetMediaType.webp &&
            _u32le(bytes, 4) + 8 != bytes.length) {
      throw const PresentationAssetException(
        PresentationAssetErrorKind.corrupt,
      );
    }
    final decoder = switch (type) {
      PresentationAssetMediaType.png => image.PngDecoder(),
      PresentationAssetMediaType.jpeg => image.JpegDecoder(),
      PresentationAssetMediaType.webp => image.WebPDecoder(),
    };
    try {
      final info = decoder.startDecode(bytes);
      if (info == null) {
        throw const PresentationAssetException(
          PresentationAssetErrorKind.corrupt,
        );
      }
      if (info.width < 1 ||
          info.height < 1 ||
          info.width > maximumDimension ||
          info.height > maximumDimension ||
          info.width * info.height > maximumPixels) {
        throw const PresentationAssetException(
          PresentationAssetErrorKind.dimensions,
        );
      }
      if (decoder.decodeFrame(0) == null) {
        throw const PresentationAssetException(
          PresentationAssetErrorKind.corrupt,
        );
      }
    } on PresentationAssetException {
      rethrow;
    } catch (_) {
      throw const PresentationAssetException(
        PresentationAssetErrorKind.corrupt,
      );
    }
    return type;
  }

  _ParsedAsset _parse(
    Uint8List value,
    String assetId,
    PresentationAssetTarget target,
    String? entryId,
    String mediaWire,
  ) {
    const header = 84;
    if (value.length <= header + 16 ||
        ascii.decode(value.sublist(0, 8)) != _magic ||
        _u16(value, 8) != 1 ||
        _u16(value, 10) != 2 ||
        _u16(value, 12) != 1 ||
        _u16(value, 14) != target.id ||
        _u16(value, 18) != 0 ||
        VaultProtocolBytes.hexEncode(Uint8List.sublistView(value, 28, 44)) !=
            assetId.replaceAll('-', '') ||
        (entryId == null
            ? value.sublist(44, 60).any((b) => b != 0)
            : VaultProtocolBytes.hexEncode(
                    Uint8List.sublistView(value, 44, 60),
                  ) !=
                  entryId.replaceAll('-', ''))) {
      throw const PresentationAssetException(PresentationAssetErrorKind.scope);
    }
    final media = PresentationAssetMediaType.values
        .where((v) => v.id == _u16(value, 16) && v.wire == mediaWire)
        .firstOrNull;
    if (media == null) {
      throw const PresentationAssetException(PresentationAssetErrorKind.scope);
    }
    return _ParsedAsset(
      media,
      _u32(value, 20),
      _u32(value, 24),
      Uint8List.sublistView(value, 60, 84),
      Uint8List.sublistView(value, 84),
    );
  }

  Uint8List _aad(
    String org,
    String vault,
    String asset,
    PresentationAssetTarget target,
    String? entry,
    PresentationAssetMediaType media,
    int keyVersion,
    int generation,
  ) => VaultProtocolBytes.concat([
    VaultProtocolBytes.utf8Encode('PLDNV2AA'),
    VaultProtocolBytes.u16(1),
    VaultProtocolBytes.uuid(org),
    VaultProtocolBytes.uuid(vault),
    VaultProtocolBytes.uuid(asset),
    VaultProtocolBytes.u16(target.id),
    entry == null ? Uint8List(16) : VaultProtocolBytes.uuid(entry),
    VaultProtocolBytes.u16(media.id),
    VaultProtocolBytes.u32(keyVersion),
    VaultProtocolBytes.u32(generation),
  ]);
  bool _prefix(Uint8List b, List<int> p) {
    for (var i = 0; i < p.length; i++) {
      if (b[i] != p[i]) return false;
    }
    return true;
  }

  bool _pngEndsExactly(Uint8List b) =>
      b.length >= 12 &&
      ascii.decode(b.sublist(b.length - 8, b.length - 4), allowInvalid: true) ==
          'IEND' &&
      _u32(b, b.length - 12) == 0;
  int _u16(Uint8List b, int o) => (b[o] << 8) | b[o + 1];
  int _u32(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  int _u32le(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
  String _uuidV4() {
    final b = Uint8List.fromList(
      List.generate(16, (_) => Random.secure().nextInt(256)),
    );
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final h = VaultProtocolBytes.hexEncode(b);
    b.fillRange(0, b.length, 0);
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}

final class _AssetContext {
  _AssetContext(
    this.organizationId,
    this.keyVersion,
    this.generation,
    this.baseKey,
  );
  final String organizationId;
  final int keyVersion, generation;
  final Uint8List baseKey;
  void clear() => baseKey.fillRange(0, baseKey.length, 0);
}

final class _ParsedAsset {
  const _ParsedAsset(
    this.mediaType,
    this.keyVersion,
    this.generation,
    this.nonce,
    this.ciphertext,
  );
  final PresentationAssetMediaType mediaType;
  final int keyVersion, generation;
  final Uint8List nonce, ciphertext;
}
