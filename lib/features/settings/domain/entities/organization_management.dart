class OrganizationRole {
  const OrganizationRole({
    required this.id,
    required this.name,
    required this.permissions,
    required this.isSystem,
    required this.canAssign,
    required this.assignedMemberCount,
  });

  final String id;
  final String name;
  final int permissions;
  final bool isSystem;
  final bool canAssign;
  final int assignedMemberCount;
}

/// Permission bit exposed by the backend as assignable to the caller.
class AssignablePermission {
  const AssignablePermission({
    required this.key,
    required this.value,
    required this.canAssign,
  });

  final String key;
  final int value;
  final bool canAssign;
}

class OrganizationRoles {
  const OrganizationRoles({
    required this.items,
    required this.assignablePermissions,
  });

  final List<OrganizationRole> items;
  final List<AssignablePermission> assignablePermissions;
}

/// Active member returned by the organization-management directory.
///
/// This role/e-mail-heavy representation is used only by Team and
/// Permissions. Audit attribution continues to use its separate minimal,
/// memory-only member directory.
class OrganizationMember {
  const OrganizationMember({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.publicKey,
    required this.roles,
    required this.effectivePermissions,
    required this.isOwner,
    required this.joinedAt,
    required this.status,
  });

  final String userId;
  final String displayName;
  final String email;
  final String? publicKey;
  final List<OrganizationRole> roles;
  final int effectivePermissions;
  final bool isOwner;
  final DateTime joinedAt;
  final String status;
}

/// Role safe for use as the initial assignment of an invitation.
class InvitationRole {
  const InvitationRole({required this.id, required this.name});

  final String id;
  final String name;
}

class OrganizationInvitation {
  const OrganizationInvitation({
    required this.id,
    required this.email,
    required this.roleId,
    required this.roleName,
    required this.invitedByName,
    required this.createdAt,
    required this.sentAt,
    required this.expiresAt,
    required this.resendAvailableAt,
  });

  final String id;
  final String email;
  final String roleId;
  final String roleName;
  final String? invitedByName;
  final DateTime createdAt;
  final DateTime sentAt;
  final DateTime expiresAt;
  final DateTime resendAvailableAt;
}
