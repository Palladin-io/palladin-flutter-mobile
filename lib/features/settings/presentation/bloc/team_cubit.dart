import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/organization_management.dart';
import '../../domain/exceptions/settings_exceptions.dart';
import '../../domain/repositories/settings_repository.dart';
import 'team_state.dart';

export 'team_state.dart';

class TeamCubit extends Cubit<TeamState> {
  TeamCubit({required this.repository}) : super(const TeamState());

  final SettingsRepository repository;
  bool _canInvite = false;
  bool _canManage = false;

  /// Loads the member directory plus only the protected catalogues the caller
  /// is authorized to request.
  Future<void> load({required bool canInvite, required bool canManage}) async {
    _canInvite = canInvite;
    _canManage = canManage;
    await _fetch(showLoading: true);
  }

  Future<void> _fetch({required bool showLoading}) async {
    if (showLoading) {
      emit(state.copyWith(status: TeamStatus.loading, clearError: true));
    }
    try {
      final results = await Future.wait<Object>([
        repository.listOrganizationMembers(),
        if (_canInvite) repository.listOrganizationInvitations(),
        if (_canInvite) repository.listInvitationRoles(),
        if (_canManage) repository.listOrganizationRoles(),
      ]);
      var index = 0;
      final members = results[index++] as List<OrganizationMember>;
      final invitations = _canInvite
          ? results[index++] as List<OrganizationInvitation>
          : const <OrganizationInvitation>[];
      final invitationRoles = _canInvite
          ? results[index++] as List<InvitationRole>
          : const <InvitationRole>[];
      final rolesResult = _canManage
          ? results[index] as OrganizationRoles
          : const OrganizationRoles(items: [], assignablePermissions: []);
      emit(
        state.copyWith(
          status: TeamStatus.loaded,
          members: members,
          invitations: invitations,
          invitationRoles: invitationRoles,
          roles: rolesResult.items,
          clearError: true,
        ),
      );
    } on SettingsException catch (error) {
      emit(state.copyWith(status: TeamStatus.error, error: error.kind));
    } catch (error, stackTrace) {
      AppLogger.e(
        'Team',
        'Team load failed unexpectedly',
        error: error,
        stackTrace: stackTrace,
      );
      emit(
        state.copyWith(
          status: TeamStatus.error,
          error: SettingsErrorKind.unknown,
        ),
      );
    }
  }

  Future<void> invite({required String email, required String roleId}) {
    return _mutate(
      TeamAction.invite,
      () => repository.inviteOrganizationMember(email.trim(), roleId),
    );
  }

  Future<void> cancelInvitation(String invitationId) {
    return _mutate(
      TeamAction.cancelInvitation,
      () => repository.cancelOrganizationInvitation(invitationId),
    );
  }

  /// Resends an invitation. The backend rotates the token and enforces the
  /// cooldown authoritatively.
  Future<void> resendInvitation(String invitationId) {
    return _mutate(
      TeamAction.resendInvitation,
      () => repository.resendOrganizationInvitation(invitationId),
    );
  }

  Future<void> updateInvitationRole(String invitationId, String roleId) {
    return _mutate(
      TeamAction.updateInvitationRole,
      () => repository.updateOrganizationInvitationRole(invitationId, roleId),
    );
  }

  Future<void> updateMemberRoles(String userId, List<String> roleIds) {
    return _mutate(
      TeamAction.updateMemberRoles,
      () => repository.updateOrganizationMemberRoles(userId, roleIds),
    );
  }

  Future<void> _mutate(TeamAction action, Future<void> Function() call) async {
    emit(
      state.copyWith(
        busyAction: action,
        clearActionError: true,
        clearCompletedAction: true,
      ),
    );
    try {
      await call();
      await _fetch(showLoading: false);
      emit(state.copyWith(clearBusyAction: true, completedAction: action));
    } on SettingsException catch (error) {
      emit(state.copyWith(clearBusyAction: true, actionError: error.kind));
    } catch (error, stackTrace) {
      AppLogger.e(
        'Team',
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
