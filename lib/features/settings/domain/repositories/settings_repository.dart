import '../entities/api_key.dart';
import '../entities/org.dart';
import '../entities/organization_management.dart';

/// Domain contract for organization and API-key management.
///
/// Implemented in the data layer by `SettingsRepositoryImpl`. All
/// failures surface as `SettingsException` with a typed
/// `SettingsErrorKind` so the presentation layer can render localized
/// error messages without leaking transport details.
abstract interface class SettingsRepository {
  /// Fetches the current user's organization.
  Future<Org> getOrg();

  /// Renames the organization. Only the [name] is mutable.
  Future<void> updateOrgName(String name);

  /// Returns every API key (active and revoked) for the organization.
  Future<List<ApiKey>> listApiKeys();

  /// Creates a new API key with the supplied [name].
  ///
  /// Returns a [NewApiKey] carrying the one-time plaintext secret.
  /// SECURITY: the caller must treat the plaintext as in-memory-only —
  /// never persist it.
  Future<NewApiKey> createApiKey(String name);

  /// Revokes an API key by id. Idempotent — revoking an already-revoked
  /// key succeeds without error.
  Future<void> revokeApiKey(String keyId);

  /// Re-activates a previously revoked API key.
  Future<void> activateApiKey(String keyId);

  /// Permanently deletes an API key. Irreversible.
  Future<void> deleteApiKey(String keyId);

  Future<List<OrganizationMember>> listOrganizationMembers();

  /// Replaces the complete role set of an organization member.
  Future<void> updateOrganizationMemberRoles(
    String userId,
    List<String> roleIds,
  );

  /// Returns the caller-aware organization role catalogue.
  Future<OrganizationRoles> listOrganizationRoles();

  Future<OrganizationRole> createOrganizationRole(String name, int permissions);

  Future<OrganizationRole> updateOrganizationRole(
    String roleId,
    String name,
    int permissions,
  );

  Future<void> deleteOrganizationRole(String roleId);

  Future<List<OrganizationInvitation>> listOrganizationInvitations();

  /// Lists roles that are safe for use by new invitations.
  Future<List<InvitationRole>> listInvitationRoles();

  Future<void> inviteOrganizationMember(String email, String roleId);

  Future<void> cancelOrganizationInvitation(String invitationId);

  /// Resends a pending invitation and rotates its single-use token.
  Future<void> resendOrganizationInvitation(String invitationId);

  Future<void> updateOrganizationInvitationRole(
    String invitationId,
    String roleId,
  );
}
