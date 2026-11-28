import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/features/auth/presentation/cubit/change_password_cubit.dart';
import 'package:mobile_palladin/features/auth/presentation/cubit/totp_enroll_cubit.dart';
import 'package:mobile_palladin/features/privacy/data/consent_notice_catalog.dart';
import 'package:mobile_palladin/features/privacy/data/consent_remote_datasource.dart';
import 'package:mobile_palladin/features/privacy/domain/user_consent.dart';
import 'package:mobile_palladin/features/settings/domain/entities/api_key.dart';
import 'package:mobile_palladin/features/settings/domain/entities/org.dart';
import 'package:mobile_palladin/features/settings/domain/entities/organization_management.dart';
import 'package:mobile_palladin/features/settings/domain/exceptions/settings_exceptions.dart';
import 'package:mobile_palladin/features/settings/domain/repositories/settings_repository.dart';
import 'package:mobile_palladin/features/unlock/data/datasources/account_remote_datasource.dart';
import 'package:mobile_palladin/features/unlock/data/models/account_response.dart';
import 'package:mobile_palladin/features/unlock/data/services/identity_kdf_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_member.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/vault_members_repository.dart';

final previewSecurity = PreviewSecurityState();

class PreviewSecurityState {
  int credentialRevision = 1;
  bool totpEnabled = false;
}

Future<void> registerSettingsPreview() async {
  final settings = MemorySettingsRepository();
  await getIt.unregister<SettingsRepository>();
  getIt.registerSingleton<SettingsRepository>(settings);
  await getIt.unregister<VaultMembersRepository>();
  getIt.registerSingleton<VaultMembersRepository>(
    MemoryVaultMembersRepository(settings),
  );
  await getIt.unregister<AccountRemoteDatasource>();
  getIt.registerSingleton<AccountRemoteDatasource>(PreviewAccountDatasource());
  await getIt.unregister<ChangePasswordCubit>();
  getIt.registerFactory<ChangePasswordCubit>(PreviewChangePassword.new);
  await getIt.unregister<TotpEnrollCubit>();
  getIt.registerFactory<TotpEnrollCubit>(PreviewTotpEnroll.new);
}

/// Synthetic metadata and mutations live only for this preview process.
class MemorySettingsRepository implements SettingsRepository {
  String name = 'Northstar Studio';
  int _sequence = 10;
  final roles = <OrganizationRole>[
    const OrganizationRole(
      id: 'role-admin',
      name: 'Administrator',
      permissions: 0x7fffffff,
      isSystem: true,
      canAssign: true,
      assignedMemberCount: 1,
    ),
    const OrganizationRole(
      id: 'role-user',
      name: 'User',
      permissions: 12,
      isSystem: true,
      canAssign: true,
      assignedMemberCount: 1,
    ),
    const OrganizationRole(
      id: 'role-engineer',
      name: 'Engineering',
      permissions: 4284,
      isSystem: false,
      canAssign: true,
      assignedMemberCount: 1,
    ),
  ];
  late final members = <OrganizationMember>[
    _member('demo-user', 'Alex Morgan', 'alex@example.com', roles[0], true),
    _member(
      'demo-member-jamie',
      'Jamie Chen',
      'jamie@example.com',
      roles[2],
      false,
    ),
    _member(
      'demo-member-sam',
      'Sam Rivera',
      'sam@example.com',
      roles[1],
      false,
    ),
  ];
  final invitations = <OrganizationInvitation>[
    OrganizationInvitation(
      id: 'invite-taylor',
      email: 'taylor@example.com',
      roleId: 'role-engineer',
      roleName: 'Engineering',
      invitedByName: 'Alex Morgan',
      createdAt: DateTime.utc(2026, 11, 16),
      sentAt: DateTime.utc(2026, 11, 16),
      expiresAt: DateTime.now().add(const Duration(days: 7)),
      resendAvailableAt: DateTime.utc(2026, 11, 16),
    ),
  ];
  final keys = <ApiKey>[
    ApiKey(
      apiKeyId: 'key-development',
      name: 'Development assistants',
      keySuffix: 'DEMO',
      status: ApiKeyStatus.active,
      createdAt: DateTime.utc(2026, 10, 3),
    ),
    ApiKey(
      apiKeyId: 'key-ci',
      name: 'CI automation',
      keySuffix: 'TEST',
      status: ApiKeyStatus.active,
      createdAt: DateTime.utc(2026, 11, 5),
    ),
    ApiKey(
      apiKeyId: 'key-legacy',
      name: 'Previous workstation',
      keySuffix: 'OLD0',
      status: ApiKeyStatus.revoked,
      createdAt: DateTime.utc(2026, 9, 1),
      revokedAt: DateTime.utc(2026, 10, 20),
    ),
  ];
  static OrganizationMember _member(
    String id,
    String name,
    String email,
    OrganizationRole role,
    bool owner,
  ) => OrganizationMember(
    userId: id,
    displayName: name,
    email: email,
    publicKey: null,
    roles: [role],
    effectivePermissions: role.permissions,
    isOwner: owner,
    joinedAt: DateTime.utc(2026, 9, owner ? 1 : 12),
    status: 'Active',
  );
  T _require<T>(Iterable<T> values, bool Function(T) predicate) =>
      values.where(predicate).firstOrNull ??
      (throw const SettingsException(SettingsErrorKind.notFound));
  void _name(String value) {
    if (value.trim().isEmpty) {
      throw const SettingsException(SettingsErrorKind.validation);
    }
  }

  @override
  Future<Org> getOrg() async => Org(
    orgId: 'demo-org',
    name: name,
    planType: 'Pro',
    memberCount: members.length,
    seatUsage: members.length + invitations.length,
    seatLimit: 10,
  );
  @override
  Future<void> updateOrgName(String value) async {
    _name(value);
    name = value.trim();
  }

  @override
  Future<List<ApiKey>> listApiKeys() async => List.of(keys);
  @override
  Future<NewApiKey> createApiKey(String name) async {
    _name(name);
    final id = 'key-preview-${++_sequence}';
    final now = DateTime.now();
    keys.insert(
      0,
      ApiKey(
        apiKeyId: id,
        name: name,
        keySuffix: 'DEMO',
        status: ApiKeyStatus.active,
        createdAt: now,
      ),
    );
    return NewApiKey(
      apiKeyId: id,
      name: name,
      plaintext: 'DEMO-ONLY-NOT-A-VALID-API-KEY-$id',
      createdAt: now,
    );
  }

  void _keyStatus(String id, ApiKeyStatus status) {
    final key = _require(keys, (k) => k.apiKeyId == id);
    keys[keys.indexOf(key)] = ApiKey(
      apiKeyId: id,
      name: key.name,
      keySuffix: key.keySuffix,
      status: status,
      createdAt: key.createdAt,
      revokedAt: status == ApiKeyStatus.revoked ? DateTime.now() : null,
    );
  }

  @override
  Future<void> revokeApiKey(String keyId) async =>
      _keyStatus(keyId, ApiKeyStatus.revoked);
  @override
  Future<void> activateApiKey(String keyId) async =>
      _keyStatus(keyId, ApiKeyStatus.active);
  @override
  Future<void> deleteApiKey(String keyId) async {
    final key = _require(keys, (k) => k.apiKeyId == keyId);
    keys.remove(key);
  }

  @override
  Future<List<OrganizationMember>> listOrganizationMembers() async =>
      List.of(members);
  @override
  Future<void> updateOrganizationMemberRoles(
    String userId,
    List<String> roleIds,
  ) async {
    final member = _require(members, (m) => m.userId == userId);
    if (member.isOwner) {
      throw const SettingsException(SettingsErrorKind.forbidden);
    }
    final assigned = roleIds
        .map((id) => _require(roles, (r) => r.id == id))
        .toList();
    members[members.indexOf(member)] = OrganizationMember(
      userId: member.userId,
      displayName: member.displayName,
      email: member.email,
      publicKey: member.publicKey,
      roles: assigned,
      effectivePermissions: assigned.fold(0, (mask, r) => mask | r.permissions),
      isOwner: false,
      joinedAt: member.joinedAt,
      status: member.status,
    );
  }

  @override
  Future<OrganizationRoles> listOrganizationRoles() async => OrganizationRoles(
    items: roles
        .map(
          (r) => OrganizationRole(
            id: r.id,
            name: r.name,
            permissions: r.permissions,
            isSystem: r.isSystem,
            canAssign: r.canAssign,
            assignedMemberCount: members
                .where((m) => m.roles.any((a) => a.id == r.id))
                .length,
          ),
        )
        .toList(),
    assignablePermissions: [
      for (final p in {
        'AddUser': 1,
        'OrganizationManagement': 2,
        'VaultCreate': 4,
        'VaultManage': 8,
        'AgentManage': 16,
        'GrantManage': 32,
        'AuditView': 128,
        'ReadApiKey': 4096,
        'WriteApiKey': 8192,
      }.entries)
        AssignablePermission(key: p.key, value: p.value, canAssign: true),
    ],
  );
  @override
  Future<OrganizationRole> createOrganizationRole(
    String name,
    int permissions,
  ) async {
    _name(name);
    final role = OrganizationRole(
      id: 'role-preview-${++_sequence}',
      name: name,
      permissions: permissions,
      isSystem: false,
      canAssign: true,
      assignedMemberCount: 0,
    );
    roles.add(role);
    return role;
  }

  @override
  Future<OrganizationRole> updateOrganizationRole(
    String roleId,
    String name,
    int permissions,
  ) async {
    _name(name);
    final old = _require(roles, (r) => r.id == roleId);
    if (old.isSystem) {
      throw const SettingsException(SettingsErrorKind.forbidden);
    }
    final role = OrganizationRole(
      id: roleId,
      name: name,
      permissions: permissions,
      isSystem: false,
      canAssign: true,
      assignedMemberCount: old.assignedMemberCount,
    );
    roles[roles.indexOf(old)] = role;
    for (final member in List.of(members)) {
      if (member.roles.any((r) => r.id == roleId)) {
        await updateOrganizationMemberRoles(
          member.userId,
          member.roles.map((r) => r.id).toList(),
        );
      }
    }
    for (final invitation in List.of(invitations)) {
      if (invitation.roleId == roleId) {
        await updateOrganizationInvitationRole(invitation.id, roleId);
      }
    }
    return role;
  }

  @override
  Future<void> deleteOrganizationRole(String roleId) async {
    final role = _require(roles, (r) => r.id == roleId);
    if (role.isSystem ||
        members.any((m) => m.roles.any((r) => r.id == roleId)) ||
        invitations.any((i) => i.roleId == roleId)) {
      throw const SettingsException(SettingsErrorKind.conflict);
    }
    roles.remove(role);
  }

  @override
  Future<List<OrganizationInvitation>> listOrganizationInvitations() async =>
      List.of(invitations);
  @override
  Future<List<InvitationRole>> listInvitationRoles() async =>
      roles.map((r) => InvitationRole(id: r.id, name: r.name)).toList();
  @override
  Future<void> inviteOrganizationMember(String email, String roleId) async {
    if (!email.contains('@')) {
      throw const SettingsException(SettingsErrorKind.validation);
    }
    if (members.length + invitations.length >= 10) {
      throw const SettingsException(SettingsErrorKind.seatLimitReached);
    }
    if (invitations.any((i) => i.email == email) ||
        members.any((m) => m.email == email)) {
      throw const SettingsException(SettingsErrorKind.conflict);
    }
    final role = _require(roles, (r) => r.id == roleId);
    final now = DateTime.now();
    invitations.add(
      OrganizationInvitation(
        id: 'invite-preview-${++_sequence}',
        email: email,
        roleId: roleId,
        roleName: role.name,
        invitedByName: 'Alex Morgan',
        createdAt: now,
        sentAt: now,
        expiresAt: now.add(const Duration(days: 7)),
        resendAvailableAt: now.add(const Duration(minutes: 1)),
      ),
    );
  }

  @override
  Future<void> cancelOrganizationInvitation(String invitationId) async {
    invitations.remove(
      _require<OrganizationInvitation>(
        invitations,
        (i) => i.id == invitationId,
      ),
    );
  }

  @override
  Future<void> resendOrganizationInvitation(String invitationId) async =>
      _invitation(invitationId, resend: true);
  @override
  Future<void> updateOrganizationInvitationRole(
    String invitationId,
    String roleId,
  ) async => _invitation(invitationId, roleId: roleId);
  void _invitation(String id, {String? roleId, bool resend = false}) {
    final old = _require(invitations, (i) => i.id == id);
    final now = DateTime.now();
    if (resend && old.resendAvailableAt.isAfter(now)) {
      throw const SettingsException(SettingsErrorKind.conflict);
    }
    final role = _require(roles, (r) => r.id == (roleId ?? old.roleId));
    invitations[invitations.indexOf(old)] = OrganizationInvitation(
      id: id,
      email: old.email,
      roleId: role.id,
      roleName: role.name,
      invitedByName: old.invitedByName,
      createdAt: old.createdAt,
      sentAt: resend ? now : old.sentAt,
      expiresAt: resend ? now.add(const Duration(days: 7)) : old.expiresAt,
      resendAvailableAt: resend
          ? now.add(const Duration(minutes: 1))
          : old.resendAvailableAt,
    );
  }
}

class MemoryVaultMembersRepository implements VaultMembersRepository {
  MemoryVaultMembersRepository(this.settings);
  final MemorySettingsRepository settings;
  final _removed = <String>{};
  @override
  Future<List<VaultMember>> list(String vaultId) async => [
    for (final m in settings.members)
      VaultMember(
        id: '$vaultId:${m.userId}',
        name: m.displayName,
        addedAt: m.joinedAt,
        status: _removed.contains('$vaultId:${m.userId}')
            ? VaultMemberStatus.waitingForRotation
            : VaultMemberStatus.active,
      ),
  ];
  @override
  Future<void> requestRemoval(String memberId) async {
    if (memberId.endsWith(':demo-user')) {
      throw const VaultMembersException(VaultMembersErrorKind.protectedMember);
    }
    _removed.add(memberId);
  }
}

class MemoryConsentRemoteDataSource implements ConsentRemoteDataSource {
  final _saved = <String, UserConsent>{};
  @override
  Future<UserConsents> get(String locale, {CancelToken? cancelToken}) async =>
      UserConsents([
        for (final purpose in ['product_analytics', 'email_marketing'])
          _withNotice(purpose, locale),
      ], 60);
  UserConsent _withNotice(String purpose, String locale) {
    final old = _saved[purpose];
    return UserConsent(
      purpose: purpose,
      scope: 'account',
      status: old?.status ?? 'denied',
      revision: old?.revision ?? 1,
      activationRevision: old?.activationRevision ?? 0,
      recordedAt: old?.recordedAt,
      noticeVersion:
          old?.noticeVersion ?? consentNotice(purpose, locale)?.version,
      noticeLocale: locale,
      currentNotice: consentNotice(purpose, locale),
    );
  }

  @override
  Future<UserConsent> decide(
    ConsentDecision decision, {
    CancelToken? cancelToken,
  }) async {
    final old = _withNotice(decision.purpose, decision.locale);
    final next = UserConsent(
      purpose: decision.purpose,
      scope: 'account',
      status: decision.granted ? 'granted' : 'denied',
      revision: old.revision + 1,
      activationRevision: old.activationRevision + 1,
      recordedAt: DateTime.now(),
      noticeVersion: decision.noticeVersion,
      noticeLocale: decision.locale,
      currentNotice: consentNotice(decision.purpose, decision.locale),
    );
    _saved[decision.purpose] = next;
    return next;
  }
}

class PreviewAccountDatasource implements AccountRemoteDatasource {
  @override
  Future<AccountResponse> getAccount() async => AccountResponse(
    userId: 'demo-user',
    email: 'alex@example.com',
    kdf: IdentityKdfMetadata(
      securityVersion: 1,
      minimumSecurityVersion: 1,
      profileId: IdentityKdfProfile.id,
      kdfSalt: 'DEMO-NOT-KEY-MATERIAL',
      credentialRevision: previewSecurity.credentialRevision,
      privateKeyWrapRevision: 1,
    ),
  );
  @override
  Future<AccountResponse> getUnlockAccount() => getAccount();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Account operation unavailable in offline preview',
  );
}

class PreviewChangePassword extends Cubit<ChangePasswordState>
    implements ChangePasswordCubit {
  PreviewChangePassword() : super(const ChangePasswordInitial());
  @override
  Future<void> changePassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  }) async {
    previewSecurity.credentialRevision++;
    emit(
      ChangePasswordSuccess(
        masterKey: Uint8List(32),
        privateKey: Uint8List(32),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Password operation unavailable in offline preview',
  );
}

class PreviewTotpEnroll extends Cubit<TotpEnrollState>
    implements TotpEnrollCubit {
  PreviewTotpEnroll() : super(const TotpEnrollPasswordRequired());
  @override
  Future<void> enroll(String password) async => emit(
    const TotpEnrollReady(
      secret: 'JBSWY3DPEHPK3PXP',
      otpauthUri:
          'otpauth://totp/DEMO:alex%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=DEMO',
    ),
  );
  @override
  Future<void> confirm(String code) async {
    previewSecurity.totpEnabled = true;
    emit(
      const TotpEnrollConfirmed([
        'DEMO-CODE-0001',
        'DEMO-CODE-0002',
        'DEMO-CODE-0003',
        'DEMO-CODE-0004',
      ]),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('TOTP operation unavailable in offline preview');
}
