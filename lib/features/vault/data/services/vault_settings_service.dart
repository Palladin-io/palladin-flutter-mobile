import 'dart:io';
import 'dart:typed_data';

import '../../domain/entities/vault_entity.dart';
import '../../domain/entities/vault_plaintext.dart';
import '../datasources/vault_remote_datasource.dart';
import 'encrypted_presentation_asset_service.dart';
import 'vault_protocol/vault_protocol_signature_service.dart';
import 'vault_crypto_service.dart';

enum VaultSettingsErrorKind { locked, conflict, corrupt, network, unknown }

final class VaultSettingsException implements Exception {
  const VaultSettingsException(this.kind);
  final VaultSettingsErrorKind kind;
}

/// Performs read-authenticate-compare-encrypt-write for Vault settings.
class VaultSettingsService {
  VaultSettingsService({
    required VaultRemoteDatasource remote,
    required VaultCryptoService vaultCrypto,
    required EncryptedPresentationAssetService assets,
  }) : _remote = remote,
       _vaultCrypto = vaultCrypto,
       _assets = assets;

  final VaultRemoteDatasource _remote;
  final VaultCryptoService _vaultCrypto;
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
    final organizationId = fresh['organizationId'] as String;
    final generation = fresh['memberKeyGeneration'] as int;
    Uint8List? vaultKey;
    Uint8List? discoveryKey;
    String? uploadedAssetId;
    var committed = false;
    var ambiguous = false;
    try {
      final opened = await _vaultCrypto.openVaultProjection(
        json: fresh,
        memberPrivateKey: memberPrivateKey,
      );
      vaultKey = opened.vaultKey;
      discoveryKey = opened.vaultDiscoveryKey;
      final current = _metadata(opened.metadata);
      if (!_sameMetadata(current, _fromEntity(expected))) {
        throw const VaultSettingsException(VaultSettingsErrorKind.conflict);
      }

      var nextIcon = icon;
      if (localIconPath != null) {
        final file = File(localIconPath);
        nextIcon = await _assets.uploadFile(
          target: PresentationAssetTarget.vault,
          vaultId: expected.id,
          file: file,
          memberPrivateKey: memberPrivateKey,
        );
        uploadedAssetId = _assetId(nextIcon);
      }
      final next = MemberVaultMetadata(
        name: name,
        description: description.isEmpty ? null : description,
        icon: VaultPlaintextIcon.fromReference(nextIcon),
        color: color.isEmpty ? null : color.toUpperCase(),
        grantMode: current['grantMode'] as String,
      );
      final attempted = await _vaultCrypto.sealMemberVaultMetadata(
        currentEnvelope: envelope,
        metadata: next,
        vaultKey: vaultKey,
        organizationId: organizationId,
        vaultId: expected.id,
        memberKeyGeneration: generation,
      );
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
      discoveryKey?.fillRange(0, discoveryKey.length, 0);
    }
  }

  Future<_WriteOutcome> _observe(
    String vaultId,
    Map<String, dynamic> attempted,
  ) async {
    try {
      final observed = await _remote.getEncryptedVault(vaultId);
      final envelope = _map(observed, 'memberVaultMetadata');
      final observedDescriptor = _map(envelope, 'descriptor');
      final attemptedDescriptor = _map(attempted, 'descriptor');
      if (observedDescriptor['resourceRevision'] ==
              attemptedDescriptor['resourceRevision'] &&
          envelope['encodedSuitePayload'] == attempted['encodedSuitePayload']) {
        return _WriteOutcome.committed;
      }
      final observedRevision = BigInt.parse(
        observedDescriptor['resourceRevision'] as String,
      );
      final attemptedRevision = BigInt.parse(
        attemptedDescriptor['resourceRevision'] as String,
      );
      return observedRevision <= attemptedRevision
          ? _WriteOutcome.rejected
          : _WriteOutcome.ambiguous;
    } catch (_) {
      return _WriteOutcome.ambiguous;
    }
  }

  Map<String, dynamic> _metadata(MemberVaultMetadata canonical) => {
    'name': canonical.name,
    if (canonical.description != null) 'description': canonical.description,
    if (canonical.icon != null)
      'iconReference': _iconReference(canonical.icon!),
    if (canonical.color != null) 'color': canonical.color,
    'grantMode': canonical.grantMode,
  };

  String _iconReference(VaultPlaintextIcon icon) => switch (icon) {
    GlyphVaultIcon(:final value) => value,
    EncryptedAssetVaultIcon(:final assetId) => 'asset:$assetId',
    PublicAssetVaultIcon(:final assetId) => 'public-asset:$assetId',
    WebsiteVaultIcon(:final hostname) => 'website:$hostname',
  };

  Map<String, dynamic> _fromEntity(VaultEntity vault) => {
    'name': vault.name,
    if (vault.description != null) 'description': vault.description,
    if (vault.icon != null) 'iconReference': vault.icon,
    if (vault.color != null) 'color': vault.color,
  };

  bool _sameMetadata(Map<String, dynamic> left, Map<String, dynamic> right) =>
      canonicalizeVaultJson({
        'name': left['name'],
        if (left['description'] != null) 'description': left['description'],
        if (left['iconReference'] != null)
          'iconReference': left['iconReference'],
        if (left['color'] != null) 'color': left['color'],
      }) ==
      canonicalizeVaultJson(right);

  String? _assetId(String? reference) {
    final match = RegExp(
      r'^asset:([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}):[0-9]+$',
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
