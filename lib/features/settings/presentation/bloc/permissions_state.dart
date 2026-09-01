import '../../domain/entities/organization_management.dart';
import '../../domain/exceptions/settings_exceptions.dart';

enum PermissionsStatus { initial, loading, loaded, error }

enum PermissionsAction { create, update, delete }

class PermissionsState {
  const PermissionsState({
    this.status = PermissionsStatus.initial,
    this.roles = const [],
    this.assignablePermissions = const [],
    this.error,
    this.actionError,
    this.busyAction,
    this.completedAction,
  });

  final PermissionsStatus status;
  final List<OrganizationRole> roles;
  final List<AssignablePermission> assignablePermissions;
  final SettingsErrorKind? error;
  final SettingsErrorKind? actionError;
  final PermissionsAction? busyAction;
  final PermissionsAction? completedAction;

  PermissionsState copyWith({
    PermissionsStatus? status,
    List<OrganizationRole>? roles,
    List<AssignablePermission>? assignablePermissions,
    SettingsErrorKind? error,
    bool clearError = false,
    SettingsErrorKind? actionError,
    bool clearActionError = false,
    PermissionsAction? busyAction,
    bool clearBusyAction = false,
    PermissionsAction? completedAction,
    bool clearCompletedAction = false,
  }) {
    return PermissionsState(
      status: status ?? this.status,
      roles: roles ?? this.roles,
      assignablePermissions:
          assignablePermissions ?? this.assignablePermissions,
      error: clearError ? null : (error ?? this.error),
      actionError: clearActionError ? null : (actionError ?? this.actionError),
      busyAction: clearBusyAction ? null : (busyAction ?? this.busyAction),
      completedAction: clearCompletedAction
          ? null
          : (completedAction ?? this.completedAction),
    );
  }
}
