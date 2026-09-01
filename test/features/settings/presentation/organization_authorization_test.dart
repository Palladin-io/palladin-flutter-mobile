import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_palladin/core/permissions.dart';
import 'package:mobile_palladin/features/settings/domain/entities/organization_management.dart';
import 'package:mobile_palladin/features/settings/presentation/pages/permission_role_page.dart';
import 'package:mobile_palladin/features/settings/presentation/pages/team_detail_pages.dart';

void main() {
  test('non-delegable custom roles remain read-only', () {
    expect(canEditOrganizationRole(_role(canAssign: false)), isFalse);
    expect(canEditOrganizationRole(_role(canAssign: true)), isTrue);
    expect(
      canEditOrganizationRole(_role(canAssign: true, isSystem: true)),
      isFalse,
    );
  });

  test('owners and higher peers cannot have roles replaced client-side', () {
    const caller = Permissions.organizationManagement;
    expect(
      canEditOrganizationMemberRoles(
        member: _member(isOwner: true, permissions: caller),
        callerPermissions: caller,
      ),
      isFalse,
    );
    expect(
      canEditOrganizationMemberRoles(
        member: _member(
          isOwner: false,
          permissions: caller | Permissions.grantManage,
        ),
        callerPermissions: caller,
      ),
      isFalse,
    );
    expect(
      canEditOrganizationMemberRoles(
        member: _member(isOwner: false, permissions: caller),
        callerPermissions: caller,
      ),
      isTrue,
    );
  });
}

OrganizationRole _role({required bool canAssign, bool isSystem = false}) {
  return OrganizationRole(
    id: 'role-1',
    name: 'Role',
    permissions: 2,
    isSystem: isSystem,
    canAssign: canAssign,
    assignedMemberCount: 0,
  );
}

OrganizationMember _member({required bool isOwner, required int permissions}) {
  return OrganizationMember(
    userId: 'user-1',
    displayName: 'Member',
    email: 'member@example.com',
    publicKey: null,
    roles: const [],
    effectivePermissions: permissions,
    isOwner: isOwner,
    joinedAt: DateTime.utc(2026, 8, 1),
    status: 'Active',
  );
}
