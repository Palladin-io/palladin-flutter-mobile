import '../entities/grant.dart';

/// One page of grants in domain terms.
class GrantListPage {
  const GrantListPage({required this.grants, this.nextCursor});

  final List<Grant> grants;
  final String? nextCursor;
}

/// Abstract grant-management repository.
///
/// Lives in the domain layer; implemented in the data layer. All methods
/// throw a typed `GrantsException` on failure. No method ever returns or
/// accepts crypto material — that flows through the approval path only
/// (see CVT-58 `GrantApprovalRepository`).
abstract interface class GrantsRepository {
  /// Lists grants for [vaultId] with optional [status] / [agentId]
  /// filters and cursor pagination.
  Future<GrantListPage> listGrants(
    String vaultId, {
    String? status,
    String? agentId,
    String? cursor,
    int pageSize,
  });

  /// Lists org-wide grants (across every manageable vault) — the Approvals
  /// "history" feed. Optional [status] / [agentId] / [vaultId] / [entryId] /
  /// [query] filters and cursor pagination.
  Future<GrantListPage> listOrgGrants({
    String? status,
    String? agentId,
    String? vaultId,
    String? entryId,
    String? query,
    String? cursor,
    int pageSize,
  });

  /// Fetches a single grant by id.
  Future<Grant> getGrant(String vaultId, String grantId);

  /// Revokes a grant, optionally recording a [reason].
  Future<void> revokeGrant(String vaultId, String grantId, {String? reason});
}
