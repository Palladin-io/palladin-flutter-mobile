import 'dart:io';

import 'package:dio/dio.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/api_key.dart';
import '../../domain/entities/org.dart';
import '../../domain/entities/organization_management.dart';
import '../../domain/exceptions/settings_exceptions.dart';
import '../../domain/repositories/settings_repository.dart';
import '../datasources/settings_remote_data_source.dart';

/// Concrete implementation of [SettingsRepository].
///
/// Wraps [SettingsRemoteDataSource] and translates DioExceptions into
/// typed [SettingsException]s with semantic [SettingsErrorKind] values
/// so the presentation layer can render localized error messages.
class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl(this._dataSource);

  final SettingsRemoteDataSource _dataSource;

  @override
  Future<Org> getOrg() async {
    try {
      AppLogger.d('Settings', 'GET /api/org');
      final model = await _dataSource.getOrg();
      return model.toEntity();
    } on DioException catch (e, s) {
      AppLogger.e('Settings', 'getOrg failed', error: e, stackTrace: s);
      throw SettingsException(_classifyError(e));
    }
  }

  @override
  Future<void> updateOrgName(String name) async {
    try {
      AppLogger.d('Settings', 'PUT /api/org');
      await _dataSource.updateOrgName(name);
    } on DioException catch (e, s) {
      AppLogger.e('Settings', 'updateOrgName failed', error: e, stackTrace: s);
      throw SettingsException(_classifyError(e));
    }
  }

  @override
  Future<List<ApiKey>> listApiKeys() async {
    try {
      AppLogger.d('Settings', 'GET /api/api-keys');
      final models = await _dataSource.listApiKeys();
      return models.map((m) => m.toEntity()).toList(growable: false);
    } on DioException catch (e, s) {
      AppLogger.e('Settings', 'listApiKeys failed', error: e, stackTrace: s);
      throw SettingsException(_classifyError(e));
    }
  }

  @override
  Future<NewApiKey> createApiKey(String name) async {
    try {
      AppLogger.d('Settings', 'POST /api/api-keys');
      final model = await _dataSource.createApiKey(name);
      return model.toEntity();
    } on DioException catch (e, s) {
      AppLogger.e('Settings', 'createApiKey failed', error: e, stackTrace: s);
      throw SettingsException(_classifyError(e));
    }
  }

  @override
  Future<void> revokeApiKey(String keyId) async {
    try {
      AppLogger.d('Settings', 'DELETE /api/api-keys/$keyId');
      await _dataSource.revokeApiKey(keyId);
    } on DioException catch (e, s) {
      AppLogger.e('Settings', 'revokeApiKey failed', error: e, stackTrace: s);
      throw SettingsException(_classifyError(e));
    }
  }

  @override
  Future<void> activateApiKey(String keyId) async {
    try {
      AppLogger.d('Settings', 'POST /api/api-keys/$keyId/activate');
      await _dataSource.activateApiKey(keyId);
    } on DioException catch (e, s) {
      AppLogger.e('Settings', 'activateApiKey failed', error: e, stackTrace: s);
      throw SettingsException(_classifyError(e));
    }
  }

  @override
  Future<void> deleteApiKey(String keyId) async {
    try {
      AppLogger.d('Settings', 'DELETE /api/api-keys/$keyId/permanent');
      await _dataSource.deleteApiKey(keyId);
    } on DioException catch (e, s) {
      AppLogger.e('Settings', 'deleteApiKey failed', error: e, stackTrace: s);
      throw SettingsException(_classifyError(e));
    }
  }

  @override
  Future<List<OrganizationMember>> listOrganizationMembers() async {
    final models = await _run(
      operation: 'GET /api/organization/members',
      action: _dataSource.listOrganizationMembers,
    );
    return models.map((model) => model.toEntity()).toList(growable: false);
  }

  @override
  Future<void> updateOrganizationMemberRoles(
    String userId,
    List<String> roleIds,
  ) {
    return _run(
      operation: 'PUT /api/organization/members/$userId/roles',
      action: () => _dataSource.updateOrganizationMemberRoles(userId, roleIds),
    );
  }

  @override
  Future<OrganizationRoles> listOrganizationRoles() async {
    final model = await _run(
      operation: 'GET /api/organization/roles',
      action: _dataSource.listOrganizationRoles,
    );
    return model.toEntity();
  }

  @override
  Future<OrganizationRole> createOrganizationRole(
    String name,
    int permissions,
  ) async {
    final model = await _run(
      operation: 'POST /api/organization/roles',
      action: () => _dataSource.createOrganizationRole(name, permissions),
    );
    return model.toEntity();
  }

  @override
  Future<OrganizationRole> updateOrganizationRole(
    String roleId,
    String name,
    int permissions,
  ) async {
    final model = await _run(
      operation: 'PUT /api/organization/roles/$roleId',
      action: () =>
          _dataSource.updateOrganizationRole(roleId, name, permissions),
    );
    return model.toEntity();
  }

  @override
  Future<void> deleteOrganizationRole(String roleId) {
    return _run(
      operation: 'DELETE /api/organization/roles/$roleId',
      action: () => _dataSource.deleteOrganizationRole(roleId),
    );
  }

  @override
  Future<List<OrganizationInvitation>> listOrganizationInvitations() async {
    final models = await _run(
      operation: 'GET /api/organization/invitations',
      action: _dataSource.listOrganizationInvitations,
    );
    return models.map((model) => model.toEntity()).toList(growable: false);
  }

  @override
  Future<List<InvitationRole>> listInvitationRoles() async {
    final models = await _run(
      operation: 'GET /api/organization/invitation-roles',
      action: _dataSource.listInvitationRoles,
    );
    return models.map((model) => model.toEntity()).toList(growable: false);
  }

  @override
  Future<void> inviteOrganizationMember(String email, String roleId) {
    return _run(
      operation: 'POST /api/organization/invitations',
      action: () => _dataSource.inviteOrganizationMember(email, roleId),
    );
  }

  @override
  Future<void> cancelOrganizationInvitation(String invitationId) {
    return _run(
      operation: 'DELETE /api/organization/invitations/$invitationId',
      action: () => _dataSource.cancelOrganizationInvitation(invitationId),
    );
  }

  @override
  Future<void> resendOrganizationInvitation(String invitationId) {
    return _run(
      operation: 'POST /api/organization/invitations/$invitationId/resend',
      action: () => _dataSource.resendOrganizationInvitation(invitationId),
    );
  }

  @override
  Future<void> updateOrganizationInvitationRole(
    String invitationId,
    String roleId,
  ) {
    return _run(
      operation: 'PUT /api/organization/invitations/$invitationId/role',
      action: () =>
          _dataSource.updateOrganizationInvitationRole(invitationId, roleId),
    );
  }

  Future<T> _run<T>({
    required String operation,
    required Future<T> Function() action,
  }) async {
    try {
      AppLogger.d('Settings', operation);
      return await action();
    } on DioException catch (e, s) {
      AppLogger.e('Settings', '$operation failed', error: e, stackTrace: s);
      throw SettingsException(_classifyError(e));
    }
  }

  /// Maps a [DioException] to a typed [SettingsErrorKind].
  SettingsErrorKind _classifyError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.error is SocketException) {
      return SettingsErrorKind.networkError;
    }

    if (e.response?.statusCode == 409 &&
        _containsErrorCode(
          e.response?.data,
          'organization-seat-limit-reached',
        )) {
      return SettingsErrorKind.seatLimitReached;
    }

    if (e.response?.statusCode == 409 &&
        _containsErrorCode(
          e.response?.data,
          'organization-role-grant-manage-cutover-unavailable',
        )) {
      return SettingsErrorKind.grantManageCutoverUnavailable;
    }

    return switch (e.response?.statusCode) {
      404 => SettingsErrorKind.notFound,
      403 => SettingsErrorKind.forbidden,
      400 => SettingsErrorKind.validation,
      409 => SettingsErrorKind.conflict,
      422 => SettingsErrorKind.validation,
      _ => SettingsErrorKind.unknown,
    };
  }

  bool _containsErrorCode(Object? value, String expected) {
    if (value is List<Object?>) {
      return value.any((item) => _containsErrorCode(item, expected));
    }
    if (value is Map<Object?, Object?>) {
      if (value['code'] == expected) return true;
      return value.values.any((item) => _containsErrorCode(item, expected));
    }
    return false;
  }
}
