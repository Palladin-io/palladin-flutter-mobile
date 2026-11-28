import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/privacy/domain/user_consent.dart';
import 'package:mobile_palladin/features/settings/domain/entities/api_key.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_member.dart';

import '../../design/mobile/settings_adapters.dart';

void main() {
  test(
    'organization, roles, invitation and API key edits survive reads',
    () async {
      final repository = MemorySettingsRepository();
      await repository.updateOrgName('Preview team');
      expect((await repository.getOrg()).name, 'Preview team');
      final role = await repository.createOrganizationRole('Reviewer', 128);
      await repository.updateOrganizationMemberRoles('demo-member-sam', [
        role.id,
      ]);
      await repository.updateOrganizationRole(role.id, 'Audit reviewer', 132);
      final sam = (await repository.listOrganizationMembers()).singleWhere(
        (m) => m.userId == 'demo-member-sam',
      );
      expect(sam.roles.single.name, 'Audit reviewer');
      expect(sam.effectivePermissions, 132);
      await repository.inviteOrganizationMember('preview@example.com', role.id);
      final invitation = (await repository.listOrganizationInvitations()).last;
      await repository.updateOrganizationInvitationRole(
        invitation.id,
        'role-user',
      );
      expect(
        (await repository.listOrganizationInvitations()).last.roleName,
        'User',
      );
      await repository.cancelOrganizationInvitation(invitation.id);
      expect(
        (await repository.listOrganizationInvitations()).any(
          (i) => i.id == invitation.id,
        ),
        false,
      );
      final key = await repository.createApiKey('Preview automation');
      await repository.revokeApiKey(key.apiKeyId);
      expect(
        (await repository.listApiKeys()).first.status,
        ApiKeyStatus.revoked,
      );
      await repository.activateApiKey(key.apiKeyId);
      expect((await repository.listApiKeys()).first.isActive, true);
      await repository.deleteApiKey(key.apiKeyId);
      expect(
        (await repository.listApiKeys()).any((k) => k.apiKeyId == key.apiKeyId),
        false,
      );
    },
  );

  test('Vault removal is scoped to the selected Vault', () async {
    final repository = MemoryVaultMembersRepository(MemorySettingsRepository());
    final member = (await repository.list('vault-a'))[1];
    await repository.requestRemoval(member.id);
    expect(
      (await repository.list('vault-a'))[1].status,
      VaultMemberStatus.waitingForRotation,
    );
    expect(
      (await repository.list('vault-b'))[1].status,
      VaultMemberStatus.active,
    );
  });

  test(
    'privacy saves an in-memory receipt and preserves the other choice',
    () async {
      final source = MemoryConsentRemoteDataSource();
      final initial = (await source.get('en')).consents.first;
      await source.decide(
        ConsentDecision(
          purpose: initial.purpose,
          granted: true,
          expectedRevision: initial.revision,
          requestId: 'demo-request',
          noticeVersion: initial.currentNotice!.version,
          locale: 'en',
          source: 'mobile_settings',
        ),
      );
      final result = (await source.get('pl')).consents;
      expect(result.first.granted, true);
      expect(result.first.revision, initial.revision + 1);
      expect(result.first.currentNotice!.locale, 'pl');
      expect(result.last.granted, false);
    },
  );
}
