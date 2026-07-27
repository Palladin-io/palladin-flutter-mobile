import 'dart:typed_data';

import '../../domain/entities/member_index_entry.dart';
import '../datasources/vault_remote_datasource.dart';
import 'member_sync_service.dart';
import 'vault_rotation_crypto_service.dart';

abstract interface class MemberEntryListLoader {
  Future<List<MemberIndexEntry>> load({
    required String vaultId,
    required Uint8List memberPrivateKey,
  });

  void lock();
}

/// Loads an Entry list exclusively from the locally decrypted MemberIndex.
final class MemberEntryListService implements MemberEntryListLoader {
  MemberEntryListService({
    required VaultRemoteDatasource vaults,
    required VaultRotationCryptoService keys,
    required MemberSyncService sync,
  }) : _vaults = vaults,
       _keys = keys,
       _sync = sync;

  final VaultRemoteDatasource _vaults;
  final VaultRotationCryptoService _keys;
  final MemberSyncService _sync;

  @override
  Future<List<MemberIndexEntry>> load({
    required String vaultId,
    required Uint8List memberPrivateKey,
  }) async {
    if (memberPrivateKey.length != 32) {
      throw const FormatException('Member private key must be 32 bytes');
    }
    final context = await _vaults.getMemberVaultKeyContext(vaultId);
    Uint8List? vaultKey;
    try {
      vaultKey = await _keys.openMemberVaultKey(
        context['memberVaultKey']! as Map<String, dynamic>,
        memberPrivateKey,
      );
      await _sync.synchronize(
        vaultId: vaultId,
        vaultKey: vaultKey,
        minimumMemberKeyGeneration: context['memberKeyGeneration']! as int,
      );
      return _sync.entries(vaultId);
    } finally {
      vaultKey?.fillRange(0, vaultKey.length, 0);
    }
  }

  @override
  void lock() => _sync.lock();
}
