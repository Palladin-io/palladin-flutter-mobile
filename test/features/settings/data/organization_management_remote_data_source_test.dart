import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/settings/data/datasources/settings_remote_data_source.dart';

void main() {
  test(
    'uses the authoritative member, role, and invitation contracts',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests.add(options);
              final response = switch ((options.method, options.path)) {
                ('GET', '/api/organization/members') => {
                  'items': [_memberJson],
                },
                ('GET', '/api/organization/roles') => {
                  'items': [_roleJson],
                  'assignablePermissions': [
                    {
                      'key': 'OrganizationManagement',
                      'value': 2,
                      'canAssign': true,
                    },
                  ],
                },
                ('GET', '/api/organization/invitations') => {
                  'items': [_invitationJson],
                },
                ('GET', '/api/organization/invitation-roles') => {
                  'items': [
                    {'id': 'role-user', 'name': 'User'},
                  ],
                },
                ('POST', '/api/organization/roles') ||
                ('PUT', '/api/organization/roles/role-admin') => _roleJson,
                _ => null,
              };
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  data: response,
                  statusCode: response == null ? 204 : 200,
                ),
              );
            },
          ),
        );
      final remote = SettingsRemoteDataSource(dio);

      final members = await remote.listOrganizationMembers();
      final roles = await remote.listOrganizationRoles();
      final invitations = await remote.listOrganizationInvitations();
      final invitationRoles = await remote.listInvitationRoles();
      await remote.updateOrganizationMemberRoles('user-1', ['role-admin']);
      await remote.createOrganizationRole('Support', 2);
      await remote.updateOrganizationRole('role-admin', 'Admin', 2);
      await remote.deleteOrganizationRole('role-admin');
      await remote.inviteOrganizationMember('new@example.com', 'role-user');
      await remote.updateOrganizationInvitationRole('invite-1', 'role-user');
      await remote.resendOrganizationInvitation('invite-1');
      await remote.cancelOrganizationInvitation('invite-1');

      expect(members.single.email, 'patryk@example.com');
      expect(members.single.roles.single.name, 'Administrator');
      expect(roles.items.single.permissions, 2);
      expect(roles.assignablePermissions.single.key, 'OrganizationManagement');
      expect(invitations.single.roleId, 'role-user');
      expect(invitationRoles.single.name, 'User');

      RequestOptions request(String method, String path) => requests
          .singleWhere((item) => item.method == method && item.path == path);

      expect(request('PUT', '/api/organization/members/user-1/roles').data, {
        'roleIds': ['role-admin'],
      });
      expect(request('POST', '/api/organization/roles').data, {
        'name': 'Support',
        'permissions': 2,
      });
      expect(request('POST', '/api/organization/invitations').data, {
        'email': 'new@example.com',
        'roleId': 'role-user',
      });
      expect(
        request('PUT', '/api/organization/invitations/invite-1/role').data,
        {'roleId': 'role-user'},
      );
    },
  );
}

const _roleJson = <String, dynamic>{
  'id': 'role-admin',
  'name': 'Administrator',
  'permissions': 2,
  'isSystem': true,
  'canAssign': true,
  'assignedMemberCount': 1,
};

const _memberJson = <String, dynamic>{
  'userId': 'user-1',
  'displayName': 'Patryk',
  'email': 'patryk@example.com',
  'publicKey': null,
  'roles': [_roleJson],
  'effectivePermissions': 2,
  'isOwner': true,
  'joinedAt': '2026-08-01T10:00:00Z',
  'status': 'Active',
};

const _invitationJson = <String, dynamic>{
  'id': 'invite-1',
  'email': 'new@example.com',
  'roleId': 'role-user',
  'roleName': 'User',
  'invitedByName': 'Patryk',
  'createdAt': '2026-08-01T10:00:00Z',
  'sentAt': '2026-08-01T10:00:00Z',
  'expiresAt': '2026-08-08T10:00:00Z',
  'resendAvailableAt': '2026-08-01T10:05:00Z',
};
