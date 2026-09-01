import '../../domain/entities/organization_management.dart';

class OrganizationRoleModel {
  const OrganizationRoleModel({
    required this.id,
    required this.name,
    required this.permissions,
    required this.isSystem,
    required this.canAssign,
    required this.assignedMemberCount,
  });

  factory OrganizationRoleModel.fromJson(Map<String, dynamic> json) {
    return OrganizationRoleModel(
      id: json['id'] as String,
      name: json['name'] as String,
      permissions: json['permissions'] as int,
      isSystem: json['isSystem'] as bool,
      canAssign: json['canAssign'] as bool,
      assignedMemberCount: (json['assignedMemberCount'] as int?) ?? 0,
    );
  }

  final String id;
  final String name;
  final int permissions;
  final bool isSystem;
  final bool canAssign;
  final int assignedMemberCount;

  OrganizationRole toEntity() => OrganizationRole(
    id: id,
    name: name,
    permissions: permissions,
    isSystem: isSystem,
    canAssign: canAssign,
    assignedMemberCount: assignedMemberCount,
  );
}

class AssignablePermissionModel {
  const AssignablePermissionModel({
    required this.key,
    required this.value,
    required this.canAssign,
  });

  factory AssignablePermissionModel.fromJson(Map<String, dynamic> json) {
    return AssignablePermissionModel(
      key: json['key'] as String,
      value: json['value'] as int,
      canAssign: json['canAssign'] as bool,
    );
  }

  final String key;
  final int value;
  final bool canAssign;

  AssignablePermission toEntity() =>
      AssignablePermission(key: key, value: value, canAssign: canAssign);
}

class OrganizationRolesModel {
  const OrganizationRolesModel({
    required this.items,
    required this.assignablePermissions,
  });

  factory OrganizationRolesModel.fromJson(Map<String, dynamic> json) {
    return OrganizationRolesModel(
      items: _maps(
        json['items'],
      ).map(OrganizationRoleModel.fromJson).toList(growable: false),
      assignablePermissions: _maps(
        json['assignablePermissions'],
      ).map(AssignablePermissionModel.fromJson).toList(growable: false),
    );
  }

  final List<OrganizationRoleModel> items;
  final List<AssignablePermissionModel> assignablePermissions;

  OrganizationRoles toEntity() => OrganizationRoles(
    items: items.map((item) => item.toEntity()).toList(growable: false),
    assignablePermissions: assignablePermissions
        .map((item) => item.toEntity())
        .toList(growable: false),
  );
}

class OrganizationMemberModel {
  const OrganizationMemberModel({
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

  factory OrganizationMemberModel.fromJson(Map<String, dynamic> json) {
    return OrganizationMemberModel(
      userId: json['userId'] as String,
      displayName: json['displayName'] as String,
      email: json['email'] as String,
      publicKey: json['publicKey'] as String?,
      roles: _maps(
        json['roles'],
      ).map(OrganizationRoleModel.fromJson).toList(growable: false),
      effectivePermissions: json['effectivePermissions'] as int,
      isOwner: json['isOwner'] as bool,
      joinedAt: DateTime.parse(json['joinedAt'] as String),
      status: (json['status'] as String?) ?? 'Active',
    );
  }

  final String userId;
  final String displayName;
  final String email;
  final String? publicKey;
  final List<OrganizationRoleModel> roles;
  final int effectivePermissions;
  final bool isOwner;
  final DateTime joinedAt;
  final String status;

  OrganizationMember toEntity() => OrganizationMember(
    userId: userId,
    displayName: displayName,
    email: email,
    publicKey: publicKey,
    roles: roles.map((role) => role.toEntity()).toList(growable: false),
    effectivePermissions: effectivePermissions,
    isOwner: isOwner,
    joinedAt: joinedAt,
    status: status,
  );
}

class InvitationRoleModel {
  const InvitationRoleModel({required this.id, required this.name});

  factory InvitationRoleModel.fromJson(Map<String, dynamic> json) {
    return InvitationRoleModel(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }

  final String id;
  final String name;

  InvitationRole toEntity() => InvitationRole(id: id, name: name);
}

class OrganizationInvitationModel {
  const OrganizationInvitationModel({
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

  factory OrganizationInvitationModel.fromJson(Map<String, dynamic> json) {
    return OrganizationInvitationModel(
      id: json['id'] as String,
      email: json['email'] as String,
      roleId: json['roleId'] as String,
      roleName: json['roleName'] as String,
      invitedByName: json['invitedByName'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      sentAt: DateTime.parse(json['sentAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      resendAvailableAt: DateTime.parse(json['resendAvailableAt'] as String),
    );
  }

  final String id;
  final String email;
  final String roleId;
  final String roleName;
  final String? invitedByName;
  final DateTime createdAt;
  final DateTime sentAt;
  final DateTime expiresAt;
  final DateTime resendAvailableAt;

  OrganizationInvitation toEntity() => OrganizationInvitation(
    id: id,
    email: email,
    roleId: roleId,
    roleName: roleName,
    invitedByName: invitedByName,
    createdAt: createdAt,
    sentAt: sentAt,
    expiresAt: expiresAt,
    resendAvailableAt: resendAvailableAt,
  );
}

List<Map<String, dynamic>> _maps(Object? value) {
  return (value as List<dynamic>? ?? const <dynamic>[])
      .map((item) => item as Map<String, dynamic>)
      .toList(growable: false);
}
