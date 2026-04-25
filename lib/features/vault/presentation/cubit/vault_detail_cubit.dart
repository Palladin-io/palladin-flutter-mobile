import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/vault_entity.dart';
import '../../domain/exceptions/vault_exceptions.dart';
import '../../domain/repositories/vault_repository.dart';

/// Base class for all states of the vault detail / settings screens.
sealed class VaultDetailState {
  const VaultDetailState();
}

final class VaultDetailInitial extends VaultDetailState {
  const VaultDetailInitial();
}

final class VaultDetailLoading extends VaultDetailState {
  const VaultDetailLoading();
}

/// The vault has been fetched (or just updated). [vault] is the
/// current canonical entity for the screen to render.
final class VaultDetailLoaded extends VaultDetailState {
  const VaultDetailLoaded(this.vault);

  final VaultEntity vault;
}

/// The vault was deleted — the screen should navigate back to the
/// list. Emitted in addition to (not instead of) any list refresh.
final class VaultDetailDeleted extends VaultDetailState {
  const VaultDetailDeleted();
}

final class VaultDetailError extends VaultDetailState {
  const VaultDetailError(this.kind);

  final VaultErrorKind kind;
}

/// Drives the vault detail and settings screens.
///
/// Holds the currently-loaded vault and exposes update / delete
/// operations. Update preserves the loaded counters by re-fetching the
/// vault after a successful PUT (the update endpoint returns 204).
class VaultDetailCubit extends Cubit<VaultDetailState> {
  VaultDetailCubit({required this.repository})
      : super(const VaultDetailInitial());

  final VaultRepository repository;

  Future<void> load(String id) async {
    AppLogger.d('Vault', 'Loading vault detail id=$id');
    emit(const VaultDetailLoading());
    try {
      final vault = await repository.getVault(id);
      emit(VaultDetailLoaded(vault));
    } on VaultException catch (e) {
      AppLogger.w('Vault', 'Detail load failed: ${e.kind.name}');
      emit(VaultDetailError(e.kind));
    } catch (e, s) {
      AppLogger.e('Vault', 'Detail load failed unexpectedly',
          error: e, stackTrace: s);
      emit(const VaultDetailError(VaultErrorKind.unknown));
    }
  }

  Future<void> update(
    String id, {
    String? name,
    String? description,
    String? icon,
    String? color,
    GrantMode? grantMode,
  }) async {
    AppLogger.d('Vault', 'Updating vault id=$id');
    emit(const VaultDetailLoading());
    try {
      await repository.updateVault(
        id,
        name: name,
        description: description,
        icon: icon,
        color: color,
        grantMode: grantMode,
      );
      // Backend returns 204 — re-fetch to refresh counters / timestamps.
      final vault = await repository.getVault(id);
      emit(VaultDetailLoaded(vault));
    } on VaultException catch (e) {
      AppLogger.w('Vault', 'Update failed: ${e.kind.name}');
      emit(VaultDetailError(e.kind));
    } catch (e, s) {
      AppLogger.e('Vault', 'Update failed unexpectedly',
          error: e, stackTrace: s);
      emit(const VaultDetailError(VaultErrorKind.unknown));
    }
  }

  Future<void> delete(String id) async {
    AppLogger.d('Vault', 'Deleting vault id=$id');
    emit(const VaultDetailLoading());
    try {
      await repository.deleteVault(id);
      emit(const VaultDetailDeleted());
    } on VaultException catch (e) {
      AppLogger.w('Vault', 'Delete failed: ${e.kind.name}');
      emit(VaultDetailError(e.kind));
    } catch (e, s) {
      AppLogger.e('Vault', 'Delete failed unexpectedly',
          error: e, stackTrace: s);
      emit(const VaultDetailError(VaultErrorKind.unknown));
    }
  }
}
