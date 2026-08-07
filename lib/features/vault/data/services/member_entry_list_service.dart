import 'dart:typed_data';

import '../../domain/entities/member_index_entry.dart';
import '../datasources/vault_remote_datasource.dart';
import 'member_sync_service.dart';
import 'member_vault_key_context_store.dart';
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
    required MemberSyncCoordinator sync,
    MemberVaultKeyContextStore? keyContexts,
  }) : _vaults = vaults,
       _keys = keys,
       _sync = sync,
       _keyContexts = keyContexts ?? MemberVaultKeyContextStore();

  final VaultRemoteDatasource _vaults;
  final VaultRotationCryptoService _keys;
  final MemberSyncCoordinator _sync;
  final MemberVaultKeyContextStore _keyContexts;
  final Map<String, Future<List<MemberIndexEntry>>> _running = {};
  int _lockGeneration = 0;

  @override
  Future<List<MemberIndexEntry>> load({
    required String vaultId,
    required Uint8List memberPrivateKey,
  }) {
    if (memberPrivateKey.length != 32) {
      return Future.error(
        const FormatException('Member private key must be 32 bytes'),
      );
    }
    final active = _running[vaultId];
    if (active != null) return active;

    final generation = _lockGeneration;
    final privateKeyCopy = Uint8List.fromList(memberPrivateKey);
    final core = (() async {
      Uint8List? vaultKey;
      try {
        var context = _keyContexts.get(vaultId);
        if (context == null) {
          final remoteContext = await _vaults.getMemberVaultKeyContext(vaultId);
          _requireCurrent(generation);
          _keyContexts.install(
            vaultId: vaultId,
            memberVaultKey:
                remoteContext['memberVaultKey']! as Map<String, dynamic>,
            memberKeyGeneration: remoteContext['memberKeyGeneration']! as int,
          );
          context = _keyContexts.get(vaultId)!;
        }
        vaultKey = await _keys.openMemberVaultKey(
          context.memberVaultKey,
          privateKeyCopy,
        );
        _requireCurrent(generation);
        await _sync.synchronize(
          vaultId: vaultId,
          vaultKey: vaultKey,
          minimumMemberKeyGeneration: context.memberKeyGeneration,
        );
        _requireCurrent(generation);
        return _sync.entries(vaultId);
      } finally {
        privateKeyCopy.fillRange(0, privateKeyCopy.length, 0);
        vaultKey?.fillRange(0, vaultKey.length, 0);
      }
    })();
    late final Future<List<MemberIndexEntry>> operation;
    operation = core.whenComplete(() {
      if (identical(_running[vaultId], operation)) {
        _running.remove(vaultId);
      }
    });
    _running[vaultId] = operation;
    return operation;
  }

  @override
  void lock() {
    _lockGeneration++;
    _running.clear();
    _keyContexts.clear();
    _sync.lock();
  }

  void _requireCurrent(int generation) {
    if (generation != _lockGeneration) {
      throw const _MemberEntryListInvalidated();
    }
  }
}

final class _MemberEntryListInvalidated implements Exception {
  const _MemberEntryListInvalidated();
}
