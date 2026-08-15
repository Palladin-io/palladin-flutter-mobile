import 'dart:typed_data';

import '../../domain/entities/vault_entity.dart';
import '../../domain/entities/vault_plaintext.dart';
import '../datasources/vault_remote_datasource.dart';
import '../models/encrypted_vault_summary_model.dart';
import 'member_vault_key_context_store.dart';
import 'vault_crypto_service.dart';

final class DecryptedVaultList {
  const DecryptedVaultList({required this.vaults, required this.corruptIds});
  final List<VaultEntity> vaults;
  final List<String> corruptIds;
}

/// Decrypts Vault summaries only while an unlocked Member key is supplied.
class VaultListCryptoService {
  VaultListCryptoService({
    required VaultRemoteDatasource remote,
    required VaultCryptoService crypto,
    MemberVaultKeyContextStore? keyContexts,
    this.maximumVaults = 2000,
  }) : _remote = remote,
       _crypto = crypto,
       _keyContexts = keyContexts ?? MemberVaultKeyContextStore();

  final VaultRemoteDatasource _remote;
  final VaultCryptoService _crypto;
  final MemberVaultKeyContextStore _keyContexts;
  final int maximumVaults;

  /// Loads and opens one canonical encrypted Vault projection.
  Future<VaultEntity> loadOne(
    String vaultId,
    Uint8List memberPrivateKey,
  ) async {
    if (memberPrivateKey.length != 32) {
      throw const FormatException('Member private key must be 32 bytes');
    }
    final json = await _remote.getEncryptedVault(vaultId);
    return _decrypt(
      EncryptedVaultSummaryModel.fromJson(json),
      memberPrivateKey,
    );
  }

  /// Downloads bounded ciphertext pages and isolates corrupt Vaults.
  Future<DecryptedVaultList> load(Uint8List memberPrivateKey) async {
    if (memberPrivateKey.length != 32) {
      throw const FormatException('Member private key must be 32 bytes');
    }
    final vaults = <VaultEntity>[];
    final corrupt = <String>[];
    var offset = 0;
    var total = 1;
    while (offset < total) {
      final page = await _remote.listEncryptedVaults(offset: offset);
      total = page.total;
      if (total > maximumVaults || page.vaults.isEmpty && offset < total) {
        throw StateError('Vault list exceeds the mobile memory budget');
      }
      for (final encrypted in page.vaults) {
        try {
          vaults.add(await _decrypt(encrypted, memberPrivateKey));
        } on FormatException {
          corrupt.add(encrypted.id);
        }
      }
      offset += page.vaults.length;
    }
    return DecryptedVaultList(
      vaults: List.unmodifiable(vaults),
      corruptIds: List.unmodifiable(corrupt),
    );
  }

  Future<VaultEntity> _decrypt(
    EncryptedVaultSummaryModel summary,
    Uint8List memberPrivateKey,
  ) async {
    final privateKeyCopy = Uint8List.fromList(memberPrivateKey);
    OpenedVaultProjection? opened;
    try {
      opened = await _crypto.openVaultProjection(
        json: {
          'id': summary.id,
          'protocolVersion': summary.protocolVersion,
          'memberKeyGeneration': summary.memberKeyGeneration,
          'memberVaultMetadata': summary.memberVaultMetadata,
          'memberVaultKey': summary.memberVaultKey,
          'currentKeyEpoch': summary.currentKeyEpoch,
          'discoveryKey': summary.discoveryKey,
        },
        memberPrivateKey: privateKeyCopy,
      );
      final metadata = opened.metadata;
      _keyContexts.install(
        vaultId: summary.id,
        memberVaultKey: summary.memberVaultKey,
        memberKeyGeneration: summary.memberKeyGeneration,
      );
      return VaultEntity(
        id: summary.id,
        name: metadata.name,
        description: metadata.description,
        icon: switch (metadata.icon) {
          GlyphVaultIcon(:final value) => value,
          EncryptedAssetVaultIcon(:final assetId) => 'asset:$assetId',
          final PublicAssetVaultIcon icon => icon.reference,
          null => null,
        },
        color: metadata.color,
        grantMode: metadata.grantMode == 'full'
            ? GrantMode.full
            : GrantMode.granular,
        createdAt: summary.createdAt,
        updatedAt: summary.updatedAt,
        entryCount: summary.entryCount,
        activeGrantCount: summary.activeGrantCount,
        memberCount: summary.memberCount,
      );
    } finally {
      privateKeyCopy.fillRange(0, privateKeyCopy.length, 0);
      opened?.vaultKey.fillRange(0, opened.vaultKey.length, 0);
      opened?.vaultDiscoveryKey?.fillRange(
        0,
        opened.vaultDiscoveryKey!.length,
        0,
      );
    }
  }

  void lock() => _keyContexts.clear();
}
