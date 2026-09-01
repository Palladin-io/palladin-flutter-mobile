import '../../domain/entities/organization_management.dart';
import '../../domain/exceptions/settings_exceptions.dart';

enum TeamStatus { initial, loading, loaded, error }

enum TeamAction {
  invite,
  cancelInvitation,
  resendInvitation,
  updateInvitationRole,
  updateMemberRoles,
}

class TeamState {
  const TeamState({
    this.status = TeamStatus.initial,
    this.members = const [],
    this.invitations = const [],
    this.roles = const [],
    this.invitationRoles = const [],
    this.error,
    this.actionError,
    this.busyAction,
    this.completedAction,
  });

  final TeamStatus status;
  final List<OrganizationMember> members;
  final List<OrganizationInvitation> invitations;
  final List<OrganizationRole> roles;
  final List<InvitationRole> invitationRoles;
  final SettingsErrorKind? error;
  final SettingsErrorKind? actionError;
  final TeamAction? busyAction;
  final TeamAction? completedAction;

  TeamState copyWith({
    TeamStatus? status,
    List<OrganizationMember>? members,
    List<OrganizationInvitation>? invitations,
    List<OrganizationRole>? roles,
    List<InvitationRole>? invitationRoles,
    SettingsErrorKind? error,
    bool clearError = false,
    SettingsErrorKind? actionError,
    bool clearActionError = false,
    TeamAction? busyAction,
    bool clearBusyAction = false,
    TeamAction? completedAction,
    bool clearCompletedAction = false,
  }) {
    return TeamState(
      status: status ?? this.status,
      members: members ?? this.members,
      invitations: invitations ?? this.invitations,
      roles: roles ?? this.roles,
      invitationRoles: invitationRoles ?? this.invitationRoles,
      error: clearError ? null : (error ?? this.error),
      actionError: clearActionError ? null : (actionError ?? this.actionError),
      busyAction: clearBusyAction ? null : (busyAction ?? this.busyAction),
      completedAction: clearCompletedAction
          ? null
          : (completedAction ?? this.completedAction),
    );
  }
}
