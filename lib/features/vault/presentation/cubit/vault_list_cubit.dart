import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/vault_entity.dart';
import '../../domain/exceptions/vault_exceptions.dart';
import '../../domain/repositories/vault_repository.dart';
import '../../data/services/vault_list_crypto_service.dart';
import 'vault_list_state.dart';

export 'vault_list_state.dart';

/// Drives the vault-list screen.
///
/// Two operations are exposed:
///
///   * [loadVaults] — fetches the canonical list from the backend and
///     emits [VaultListLoaded] (or [VaultListError] on failure).
///   * [deleteVault] — deletes a vault by id, then re-fetches the
///     list so counters stay consistent.
///
/// All errors surface as [VaultListError] carrying a typed
/// [VaultErrorKind] so the UI can render a localized message.
class VaultListCubit extends Cubit<VaultListState> {
  VaultListCubit({required this.repository, required this.listService})
    : super(const VaultListInitial());

  final VaultRepository repository;
  final VaultListCryptoService listService;
  int _loadGeneration = 0;

  Future<void> loadIfNeeded(Uint8List? privateKey) async {
    if (state is VaultListLoaded) return;
    await loadVaults(privateKey);
  }

  void appendVault(VaultEntity vault) {
    final current = state;
    if (current is VaultListLoaded) {
      emit(VaultListLoaded([vault, ...current.vaults]));
    }
  }

  void removeVault(String id) {
    final current = state;
    if (current is VaultListLoaded) {
      emit(VaultListLoaded(current.vaults.where((v) => v.id != id).toList()));
    }
  }

  void updateVault(VaultEntity updated) {
    final current = state;
    if (current is VaultListLoaded) {
      emit(
        VaultListLoaded(
          current.vaults.map((v) => v.id == updated.id ? updated : v).toList(),
        ),
      );
    }
  }

  Future<void> loadVaults(Uint8List? privateKey) async {
    final generation = ++_loadGeneration;
    if (privateKey == null) {
      emit(const VaultListLocked());
      return;
    }
    AppLogger.d('Vault', 'Loading vault list');
    emit(const VaultListLoading());
    try {
      final result = await listService.load(privateKey);
      if (generation != _loadGeneration || isClosed) return;
      AppLogger.i('Vault', 'Loaded ${result.vaults.length} Vault projections');
      emit(VaultListLoaded(result.vaults, corruptVaultIds: result.corruptIds));
    } on VaultException catch (e) {
      if (generation != _loadGeneration || isClosed) return;
      AppLogger.w('Vault', 'Vault list load failed: ${e.kind.name}');
      emit(VaultListError(e.kind));
    } catch (e, s) {
      if (generation != _loadGeneration || isClosed) return;
      AppLogger.e(
        'Vault',
        'Vault list load failed unexpectedly',
        error: e,
        stackTrace: s,
      );
      emit(const VaultListError(VaultErrorKind.unknown));
    }
  }

  /// Drops every decrypted display value as soon as the screen locks.
  void lock() {
    _loadGeneration++;
    emit(const VaultListLocked());
  }

  Future<void> deleteVault(String id) async {
    AppLogger.d('Vault', 'Deleting vault id=$id');
    final before = state;
    emit(const VaultListLoading());
    try {
      await repository.deleteVault(id);
      AppLogger.i('Vault', 'Vault deleted');
      if (before is VaultListLoaded) {
        emit(
          VaultListLoaded(
            before.vaults.where((vault) => vault.id != id).toList(),
            corruptVaultIds: before.corruptVaultIds,
          ),
        );
      } else {
        emit(const VaultListInitial());
      }
    } on VaultException catch (e) {
      AppLogger.w('Vault', 'Delete failed: ${e.kind.name}');
      emit(VaultListError(e.kind));
    } catch (e, s) {
      AppLogger.e(
        'Vault',
        'Delete failed unexpectedly',
        error: e,
        stackTrace: s,
      );
      emit(const VaultListError(VaultErrorKind.unknown));
    }
  }
}
