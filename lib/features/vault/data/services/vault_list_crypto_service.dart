import 'dart:convert';
import 'dart:typed_data';

import '../../domain/entities/vault_entity.dart';
import '../datasources/vault_remote_datasource.dart';
import '../models/encrypted_vault_summary_model.dart';
import 'vault_protocol/vault_protocol_aad.dart';
import 'vault_protocol/vault_protocol_envelope_service.dart';
import 'vault_protocol/vault_protocol_kdf.dart';
import 'vault_rotation_crypto_service.dart';

final class DecryptedVaultList {
  const DecryptedVaultList({required this.vaults, required this.corruptIds});
  final List<VaultEntity> vaults;
  final List<String> corruptIds;
}

/// Decrypts Vault summaries only while an unlocked Member key is supplied.
class VaultListCryptoService {
  VaultListCryptoService({
    required VaultRemoteDatasource remote,
    required VaultRotationCryptoService keys,
    required VaultProtocolEnvelopeService envelopes,
    this.maximumVaults = 2000,
  }) : _remote = remote,
       _keys = keys,
       _envelopes = envelopes;

  final VaultRemoteDatasource _remote;
  final VaultRotationCryptoService _keys;
  final VaultProtocolEnvelopeService _envelopes;
  final int maximumVaults;

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
    Uint8List? vaultKey;
    Uint8List? metadataKey;
    Uint8List? plaintext;
    try {
      vaultKey = await _keys.openMemberVaultKey(
        summary.memberVaultKey,
        memberPrivateKey,
      );
      final envelope = summary.memberVaultMetadata;
      final header = Map<String, dynamic>.from(envelope['header'] as Map);
      metadataKey = deriveVaultProjectionKey(
        vaultKey,
        VaultKdfContext(
          purpose: VaultKdfPurpose.memberVaultMetadata,
          resourceKind: 1,
          organizationId: envelope['organizationId'] as String,
          vaultId: summary.id,
          keyVersion: header['keyVersion'] as int,
          memberKeyGeneration: header['memberKeyGeneration'] as int,
        ),
      );
      plaintext = await _envelopes.decrypt(
        profile: VaultAadProfile.memberVaultMetadata,
        envelope: envelope,
        key: metadataKey,
        expected: VaultEnvelopeExpectations(
          aadContext: envelope,
          minimumMemberKeyGeneration: summary.memberKeyGeneration,
        ),
      );
      final decoded = jsonDecode(utf8.decode(plaintext));
      if (decoded is! Map) {
        throw const FormatException('Vault metadata must be an object');
      }
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
      return VaultEntity(
        id: summary.id,
        name: name,
        description: metadata['description'] as String?,
        icon: metadata['iconReference'] as String?,
        color: metadata['color'] as String?,
        grantMode: GrantMode.granular,
        createdAt: summary.createdAt,
        updatedAt: summary.updatedAt,
        entryCount: summary.entryCount,
        activeGrantCount: summary.activeGrantCount,
        memberCount: summary.memberCount,
      );
    } finally {
      vaultKey?.fillRange(0, vaultKey.length, 0);
      metadataKey?.fillRange(0, metadataKey.length, 0);
      plaintext?.fillRange(0, plaintext.length, 0);
    }
  }
}
