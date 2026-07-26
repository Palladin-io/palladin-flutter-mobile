import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/entities/vault_entity.dart';
import '../datasources/vault_remote_datasource.dart';
import 'encrypted_presentation_asset_service.dart';
import 'vault_protocol/vault_protocol_aad.dart';
import 'vault_protocol/vault_protocol_bytes.dart';
import 'vault_protocol/vault_protocol_envelope_service.dart';
import 'vault_protocol/vault_protocol_kdf.dart';
import 'vault_protocol/vault_protocol_signature_service.dart';
import 'vault_rotation_crypto_service.dart';

enum VaultSettingsErrorKind { locked, conflict, corrupt, network, unknown }

final class VaultSettingsException implements Exception {
  const VaultSettingsException(this.kind);
  final VaultSettingsErrorKind kind;
}

/// Performs read-authenticate-compare-encrypt-write for Vault settings.
class VaultSettingsService {
  VaultSettingsService({
    required VaultRemoteDatasource remote,
    required VaultRotationCryptoService keys,
    required VaultEnvelopeCryptography envelopes,
    required EncryptedPresentationAssetService assets,
  }) : _remote = remote,
       _keys = keys,
       _envelopes = envelopes,
       _assets = assets;

  final VaultRemoteDatasource _remote;
  final VaultRotationCryptoService _keys;
  final VaultEnvelopeCryptography _envelopes;
  final EncryptedPresentationAssetService _assets;

  Future<VaultEntity> update({
    required VaultEntity expected,
    required String name,
    required String description,
    required String icon,
    required String color,
    required Uint8List memberPrivateKey,
    String? localIconPath,
  }) async {
    if (memberPrivateKey.length != 32) {
      throw const VaultSettingsException(VaultSettingsErrorKind.locked);
    }
    Map<String, dynamic> fresh;
    try {
      fresh = await _remote.getEncryptedVault(expected.id);
    } on FormatException {
      throw const VaultSettingsException(VaultSettingsErrorKind.corrupt);
    } catch (_) {
      throw const VaultSettingsException(VaultSettingsErrorKind.network);
    }
    final envelope = _map(fresh, 'memberVaultMetadata');
    final memberVaultKey = _map(fresh, 'memberVaultKey');
    final epoch = _map(fresh, 'currentKeyEpoch');
    final organizationId = fresh['organizationId'] as String;
    final generation = fresh['memberKeyGeneration'] as int;
    final keyVersion = epoch['vaultKeyVersion'] as int;
    Uint8List? vaultKey;
    Uint8List? metadataKey;
    Uint8List? plaintext;
    String? uploadedAssetId;
    var committed = false;
    var ambiguous = false;
    try {
      vaultKey = await _keys.openMemberVaultKey(
        memberVaultKey,
        memberPrivateKey,
      );
      metadataKey = deriveVaultProjectionKey(
        vaultKey,
        VaultKdfContext(
          purpose: VaultKdfPurpose.memberVaultMetadata,
          resourceKind: 1,
          organizationId: organizationId,
          vaultId: expected.id,
          keyVersion: keyVersion,
          memberKeyGeneration: generation,
        ),
      );
      plaintext = await _envelopes.decrypt(
        profile: VaultAadProfile.memberVaultMetadata,
        envelope: envelope,
        key: metadataKey,
        expected: VaultEnvelopeExpectations(
          aadContext: envelope,
          minimumMemberKeyGeneration: generation,
        ),
      );
      final current = _metadata(plaintext);
      if (!_sameMetadata(current, _fromEntity(expected))) {
        throw const VaultSettingsException(VaultSettingsErrorKind.conflict);
      }

      var nextIcon = icon;
      if (localIconPath != null) {
        final file = File(localIconPath);
        final bytes = await file.readAsBytes();
        try {
          final mediaType = _mediaType(localIconPath);
          nextIcon = await _assets.encryptAndUpload(
            organizationId: organizationId,
            vaultId: expected.id,
            vaultKey: vaultKey,
            plaintext: bytes,
            mediaType: mediaType,
            keyVersion: keyVersion,
            memberKeyGeneration: generation,
          );
          uploadedAssetId = _assetId(nextIcon);
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      }
      final next = <String, dynamic>{
        'name': name,
        if (description.isNotEmpty) 'description': description,
        'iconReference': nextIcon,
        'color': color,
      };
      final currentRevision = BigInt.tryParse(
        envelope['metadataRevision'] as String,
      );
      if (currentRevision == null || currentRevision < BigInt.zero) {
        throw const VaultSettingsException(VaultSettingsErrorKind.corrupt);
      }
      final revision = (currentRevision + BigInt.one).toString();
      final context = <String, Object?>{
        'organizationId': organizationId,
        'vaultId': expected.id,
        'metadataRevision': revision,
        'header': {
          'protocolVersion': 2,
          'algorithmSuite': 1,
          'resourceKind': 1,
          'projectionKind': 1,
          'resourceRevision': revision,
          'keyVersion': keyVersion,
          'memberKeyGeneration': generation,
          'nonce': '',
        },
      };
      final nextBytes = VaultProtocolBytes.utf8Encode(
        canonicalizeVaultJson(next),
      );
      late final Map<String, String> encrypted;
      try {
        encrypted = await _envelopes.encrypt(
          profile: VaultAadProfile.memberVaultMetadata,
          context: context,
          plaintext: nextBytes,
          key: metadataKey,
        );
      } finally {
        nextBytes.fillRange(0, nextBytes.length, 0);
      }
      final attempted = <String, dynamic>{
        ...context,
        'header': {...context['header']! as Map, 'nonce': encrypted['nonce']},
        'ciphertext': encrypted['ciphertext'],
      };
      try {
        final response = await _remote.replaceEncryptedMetadata(
          expected.id,
          attempted,
        );
        if (response.statusCode == 400 || response.statusCode == 409) {
          throw const VaultSettingsException(VaultSettingsErrorKind.conflict);
        }
        committed = true;
      } on VaultSettingsException {
        rethrow;
      } catch (_) {
        final outcome = await _observe(expected.id, attempted);
        if (outcome == _WriteOutcome.committed) {
          committed = true;
        } else if (outcome == _WriteOutcome.rejected) {
          throw const VaultSettingsException(VaultSettingsErrorKind.network);
        } else {
          ambiguous = true;
          throw const VaultSettingsException(VaultSettingsErrorKind.network);
        }
      }
      final previousAssetId = _assetId(current['iconReference'] as String?);
      if (previousAssetId != null &&
          previousAssetId != uploadedAssetId &&
          current['iconReference'] != nextIcon) {
        try {
          await _assets.delete(expected.id, previousAssetId);
        } catch (_) {
          // Metadata already committed; orphan cleanup is safely retryable.
        }
      }
      return VaultEntity(
        id: expected.id,
        name: name,
        description: description.isEmpty ? null : description,
        icon: nextIcon,
        color: color,
        grantMode: expected.grantMode,
        createdAt: expected.createdAt,
        updatedAt: DateTime.now(),
        entryCount: expected.entryCount,
        activeGrantCount: expected.activeGrantCount,
        memberCount: expected.memberCount,
        wrappedVK: expected.wrappedVK,
      );
    } on VaultSettingsException {
      rethrow;
    } on FormatException {
      throw const VaultSettingsException(VaultSettingsErrorKind.corrupt);
    } catch (_) {
      throw const VaultSettingsException(VaultSettingsErrorKind.unknown);
    } finally {
      if (uploadedAssetId != null && !committed && !ambiguous) {
        try {
          await _assets.delete(expected.id, uploadedAssetId);
        } catch (_) {
          // Compensating cleanup is best effort and contains no plaintext.
        }
      }
      vaultKey?.fillRange(0, vaultKey.length, 0);
      metadataKey?.fillRange(0, metadataKey.length, 0);
      plaintext?.fillRange(0, plaintext.length, 0);
    }
  }

  Future<_WriteOutcome> _observe(
    String vaultId,
    Map<String, dynamic> attempted,
  ) async {
    try {
      final observed = await _remote.getEncryptedVault(vaultId);
      final envelope = _map(observed, 'memberVaultMetadata');
      if (envelope['metadataRevision'] == attempted['metadataRevision'] &&
          envelope['ciphertext'] == attempted['ciphertext'] &&
          _map(envelope, 'header')['nonce'] ==
              _map(attempted, 'header')['nonce']) {
        return _WriteOutcome.committed;
      }
      final observedRevision = BigInt.parse(
        envelope['metadataRevision'] as String,
      );
      final attemptedRevision = BigInt.parse(
        attempted['metadataRevision'] as String,
      );
      return observedRevision <= attemptedRevision
          ? _WriteOutcome.rejected
          : _WriteOutcome.ambiguous;
    } catch (_) {
      return _WriteOutcome.ambiguous;
    }
  }

  Map<String, dynamic> _metadata(Uint8List plaintext) {
    final decoded = jsonDecode(utf8.decode(plaintext));
    if (decoded is! Map) throw const FormatException('Malformed metadata');
    final metadata = Map<String, dynamic>.from(decoded);
    const allowed = {'name', 'description', 'iconReference', 'color'};
    if (metadata.keys.any((key) => !allowed.contains(key)) ||
        metadata['name'] is! String ||
        (metadata['description'] != null &&
            metadata['description'] is! String) ||
        (metadata['iconReference'] != null &&
            metadata['iconReference'] is! String) ||
        (metadata['color'] != null && metadata['color'] is! String)) {
      throw const FormatException('Malformed Vault metadata');
    }
    final name = metadata['name'] as String;
    if (name.isEmpty || name.length > 256) {
      throw const FormatException('Invalid Vault name');
    }
    return metadata;
  }

  Map<String, dynamic> _fromEntity(VaultEntity vault) => {
    'name': vault.name,
    if (vault.description != null) 'description': vault.description,
    if (vault.icon != null) 'iconReference': vault.icon,
    if (vault.color != null) 'color': vault.color,
  };

  bool _sameMetadata(Map<String, dynamic> left, Map<String, dynamic> right) =>
      canonicalizeVaultJson(left) == canonicalizeVaultJson(right);

  PresentationAssetMediaType _mediaType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return PresentationAssetMediaType.png;
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return PresentationAssetMediaType.jpeg;
    }
    if (lower.endsWith('.webp')) return PresentationAssetMediaType.webp;
    throw const FormatException('Unsupported icon media type');
  }

  String? _assetId(String? reference) {
    final match = RegExp(
      r'^asset:([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$',
    ).firstMatch(reference ?? '');
    return match?.group(1);
  }

  Map<String, dynamic> _map(Map<String, dynamic> value, String key) {
    final nested = value[key];
    if (nested is! Map) throw FormatException('$key must be an object');
    return Map<String, dynamic>.from(nested);
  }
}

enum _WriteOutcome { committed, rejected, ambiguous }
