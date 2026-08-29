import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../domain/entities/member_index_entry.dart';
import '../datasources/vault_remote_datasource.dart';
import 'member_sync_service.dart';
import 'member_sync_session_authority_provider.dart';
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
    required MemberSyncSessionAuthorityProvider authorityProvider,
    MemberVaultKeyContextStore? keyContexts,
  }) : _vaults = vaults,
       _keys = keys,
       _sync = sync,
       _authorityProvider = authorityProvider,
       _keyContexts = keyContexts ?? MemberVaultKeyContextStore();

  final VaultRemoteDatasource _vaults;
  final VaultRotationCryptoService _keys;
  final MemberSyncCoordinator _sync;
  final MemberSyncSessionAuthorityProvider _authorityProvider;
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
      try {
        final authority = await _authorityProvider.current();
        var currentContext =
            _keyContexts.get(vaultId) ??
            await _refreshKeyContext(vaultId, generation);
        for (var attempt = 0; attempt < 2; attempt += 1) {
          Uint8List? vaultKey;
          try {
            vaultKey = await _keys.openMemberVaultKey(
              currentContext.memberVaultKey,
              privateKeyCopy,
            );
            _requireCurrent(generation);
            await _sync.synchronize(
              vaultId: vaultId,
              vaultKey: vaultKey,
              minimumMemberKeyGeneration: currentContext.memberKeyGeneration,
              authority: authority,
              authoritativeMemberVaultKey: currentContext.memberVaultKey,
            );
            _requireCurrent(generation);
            return _sync.entries(vaultId);
          } on MemberVaultKeyContextStaleException catch (error) {
            if (attempt != 0 ||
                error.requiredGeneration <=
                    currentContext.memberKeyGeneration) {
              rethrow;
            }
            currentContext = await _refreshKeyContext(vaultId, generation);
            if (currentContext.memberKeyGeneration < error.requiredGeneration) {
              rethrow;
            }
          } finally {
            vaultKey?.fillRange(0, vaultKey.length, 0);
          }
        }
        throw StateError('Member key context retry exhausted');
      } on DioException catch (error) {
        if (const {401, 403, 404}.contains(error.response?.statusCode)) {
          await _sync.purgeVault(vaultId);
          rethrow;
        }
        final authority = await _authorityProvider.current();
        await _sync.unlockCached(
          vaultId: vaultId,
          memberPrivateKey: privateKeyCopy,
          authority: authority,
        );
        _requireCurrent(generation);
        return _sync.entries(vaultId);
      } finally {
        privateKeyCopy.fillRange(0, privateKeyCopy.length, 0);
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

  Future<MemberVaultKeyContext> _refreshKeyContext(
    String vaultId,
    int generation,
  ) async {
    final remoteContext = await _vaults.getMemberVaultKeyContext(vaultId);
    _requireCurrent(generation);
    _keyContexts.install(
      vaultId: vaultId,
      memberVaultKey: remoteContext['memberVaultKey']! as Map<String, dynamic>,
      memberKeyGeneration: remoteContext['memberKeyGeneration']! as int,
    );
    return _keyContexts.get(vaultId)!;
  }
}

final class _MemberEntryListInvalidated implements Exception {
  const _MemberEntryListInvalidated();
}
