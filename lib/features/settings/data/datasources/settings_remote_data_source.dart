import 'package:dio/dio.dart';

import '../models/api_key_model.dart';
import '../models/org_model.dart';
import '../models/organization_management_models.dart';

class SettingsRemoteDataSource {
  SettingsRemoteDataSource(this._dio);

  final Dio _dio;

  Future<OrgModel> getOrg() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/org');
    final data = response.data;
    if (data == null) {
      throw _emptyBody(response);
    }
    return OrgModel.fromJson(data);
  }

  Future<void> updateOrgName(String name) async {
    await _dio.put<void>('/api/org', data: {'name': name});
  }

  Future<List<ApiKeyModel>> listApiKeys() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/api-keys');
    final data = response.data;
    if (data == null) {
      throw _emptyBody(response);
    }
    final raw = (data['items'] as List<dynamic>? ?? const <dynamic>[]);
    return raw
        .map((e) => ApiKeyModel.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<NewApiKeyModel> createApiKey(String name) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/api-keys',
      data: {'name': name},
    );
    final data = response.data;
    if (data == null) {
      throw _emptyBody(response);
    }
    return NewApiKeyModel.fromJson(data);
  }

  Future<void> revokeApiKey(String keyId) async {
    await _dio.delete<void>('/api/api-keys/$keyId');
  }

  Future<void> activateApiKey(String keyId) async {
    await _dio.post<void>('/api/api-keys/$keyId/activate');
  }

  Future<void> deleteApiKey(String keyId) async {
    await _dio.delete<void>('/api/api-keys/$keyId/permanent');
  }

  Future<List<OrganizationMemberModel>> listOrganizationMembers() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/organization/members',
    );
    final data = response.data;
    if (data == null) throw _emptyBody(response);
    return (data['items'] as List<dynamic>? ?? const <dynamic>[])
        .map(
          (item) =>
              OrganizationMemberModel.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  Future<void> updateOrganizationMemberRoles(
    String userId,
    List<String> roleIds,
  ) async {
    await _dio.put<Map<String, dynamic>>(
      '/api/organization/members/$userId/roles',
      data: {'roleIds': roleIds},
    );
  }

  Future<OrganizationRolesModel> listOrganizationRoles() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/organization/roles',
    );
    final data = response.data;
    if (data == null) throw _emptyBody(response);
    return OrganizationRolesModel.fromJson(data);
  }

  Future<OrganizationRoleModel> createOrganizationRole(
    String name,
    int permissions,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/organization/roles',
      data: {'name': name, 'permissions': permissions},
    );
    final data = response.data;
    if (data == null) throw _emptyBody(response);
    return OrganizationRoleModel.fromJson(data);
  }

  Future<OrganizationRoleModel> updateOrganizationRole(
    String roleId,
    String name,
    int permissions,
  ) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/organization/roles/$roleId',
      data: {'name': name, 'permissions': permissions},
    );
    final data = response.data;
    if (data == null) throw _emptyBody(response);
    return OrganizationRoleModel.fromJson(data);
  }

  Future<void> deleteOrganizationRole(String roleId) async {
    await _dio.delete<void>('/api/organization/roles/$roleId');
  }

  Future<List<OrganizationInvitationModel>>
  listOrganizationInvitations() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/organization/invitations',
    );
    final data = response.data;
    if (data == null) throw _emptyBody(response);
    return (data['items'] as List<dynamic>? ?? const <dynamic>[])
        .map(
          (item) => OrganizationInvitationModel.fromJson(
            item as Map<String, dynamic>,
          ),
        )
        .toList(growable: false);
  }

  Future<List<InvitationRoleModel>> listInvitationRoles() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/organization/invitation-roles',
    );
    final data = response.data;
    if (data == null) throw _emptyBody(response);
    return (data['items'] as List<dynamic>? ?? const <dynamic>[])
        .map(
          (item) => InvitationRoleModel.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  Future<void> inviteOrganizationMember(String email, String roleId) async {
    await _dio.post<void>(
      '/api/organization/invitations',
      data: {'email': email, 'roleId': roleId},
    );
  }

  Future<void> cancelOrganizationInvitation(String invitationId) async {
    await _dio.delete<void>('/api/organization/invitations/$invitationId');
  }

  Future<void> resendOrganizationInvitation(String invitationId) async {
    await _dio.post<Map<String, dynamic>>(
      '/api/organization/invitations/$invitationId/resend',
      data: const <String, dynamic>{},
    );
  }

  Future<void> updateOrganizationInvitationRole(
    String invitationId,
    String roleId,
  ) async {
    await _dio.put<void>(
      '/api/organization/invitations/$invitationId/role',
      data: {'roleId': roleId},
    );
  }

  DioException _emptyBody(Response<dynamic> response) => DioException(
    requestOptions: response.requestOptions,
    response: response,
    type: DioExceptionType.badResponse,
    error: 'Empty response body',
  );
}
