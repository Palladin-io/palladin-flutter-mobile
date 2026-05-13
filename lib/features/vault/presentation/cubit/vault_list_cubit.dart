import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/vault_entity.dart';
import '../../domain/exceptions/vault_exceptions.dart';
import '../../domain/repositories/vault_repository.dart';
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
  VaultListCubit({required this.repository})
      : super(const VaultListInitial());

  final VaultRepository repository;

  Future<void> loadIfNeeded() async {
    if (state is VaultListLoaded) return;
    await loadVaults();
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
      emit(VaultListLoaded(
        current.vaults.where((v) => v.id != id).toList(),
      ));
    }
  }

  void updateVault(VaultEntity updated) {
    final current = state;
    if (current is VaultListLoaded) {
      emit(VaultListLoaded(
        current.vaults.map((v) => v.id == updated.id ? updated : v).toList(),
      ));
    }
  }

  Future<void> loadVaults() async {
    AppLogger.d('Vault', 'Loading vault list');
    emit(const VaultListLoading());
    try {
      final vaults = await repository.listVaults();
      AppLogger.i('Vault', 'Loaded ${vaults.length} vaults');
      emit(VaultListLoaded(vaults));
    } on VaultException catch (e) {
      AppLogger.w('Vault', 'Vault list load failed: ${e.kind.name}');
      emit(VaultListError(e.kind));
    } catch (e, s) {
      AppLogger.e('Vault', 'Vault list load failed unexpectedly',
          error: e, stackTrace: s);
      emit(const VaultListError(VaultErrorKind.unknown));
    }
  }

  Future<void> deleteVault(String id) async {
    AppLogger.d('Vault', 'Deleting vault id=$id');
    emit(const VaultListLoading());
    try {
      await repository.deleteVault(id);
      AppLogger.i('Vault', 'Vault deleted, refreshing list');
      await loadVaults();
    } on VaultException catch (e) {
      AppLogger.w('Vault', 'Delete failed: ${e.kind.name}');
      emit(VaultListError(e.kind));
    } catch (e, s) {
      AppLogger.e('Vault', 'Delete failed unexpectedly',
          error: e, stackTrace: s);
      emit(const VaultListError(VaultErrorKind.unknown));
    }
  }
}
