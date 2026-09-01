import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/exceptions/settings_exceptions.dart';
import '../../domain/repositories/settings_repository.dart';
import 'permissions_state.dart';

export 'permissions_state.dart';

class PermissionsCubit extends Cubit<PermissionsState> {
  PermissionsCubit({required this.repository})
    : super(const PermissionsState());

  final SettingsRepository repository;

  Future<void> load({bool showLoading = true}) async {
    if (showLoading) {
      emit(state.copyWith(status: PermissionsStatus.loading, clearError: true));
    }
    try {
      final result = await repository.listOrganizationRoles();
      emit(
        state.copyWith(
          status: PermissionsStatus.loaded,
          roles: result.items,
          assignablePermissions: result.assignablePermissions,
          clearError: true,
        ),
      );
    } on SettingsException catch (error) {
      emit(state.copyWith(status: PermissionsStatus.error, error: error.kind));
    } catch (error, stackTrace) {
      AppLogger.e(
        'Permissions',
        'Role load failed unexpectedly',
        error: error,
        stackTrace: stackTrace,
      );
      emit(
        state.copyWith(
          status: PermissionsStatus.error,
          error: SettingsErrorKind.unknown,
        ),
      );
    }
  }

  Future<void> createRole(String name, int permissions) {
    return _mutate(
      PermissionsAction.create,
      () => repository.createOrganizationRole(name.trim(), permissions),
    );
  }

  /// Updates a custom role while preserving any unknown permission bits in
  /// the supplied mask.
  Future<void> updateRole(String roleId, String name, int permissions) {
    return _mutate(
      PermissionsAction.update,
      () => repository.updateOrganizationRole(roleId, name.trim(), permissions),
    );
  }

  Future<void> deleteRole(String roleId) {
    return _mutate(
      PermissionsAction.delete,
      () => repository.deleteOrganizationRole(roleId),
    );
  }

  Future<void> _mutate(
    PermissionsAction action,
    Future<Object?> Function() call,
  ) async {
    emit(
      state.copyWith(
        busyAction: action,
        clearActionError: true,
        clearCompletedAction: true,
      ),
    );
    try {
      await call();
      await load(showLoading: false);
      emit(state.copyWith(clearBusyAction: true, completedAction: action));
    } on SettingsException catch (error) {
      emit(state.copyWith(clearBusyAction: true, actionError: error.kind));
    } catch (error, stackTrace) {
      AppLogger.e(
        'Permissions',
        '${action.name} failed unexpectedly',
        error: error,
        stackTrace: stackTrace,
      );
      emit(
        state.copyWith(
          clearBusyAction: true,
          actionError: SettingsErrorKind.unknown,
        ),
      );
    }
  }

  void acknowledgeActionResult() {
    emit(state.copyWith(clearActionError: true, clearCompletedAction: true));
  }
}
