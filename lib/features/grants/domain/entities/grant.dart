/// Domain entities for the grants feature.
///
/// A "grant" is an authorization that lets a specific agent read one
/// entry (GRANULAR) or every entry in a vault (FULL). Grants are created
/// either proactively by the owner (FULL) or in response to an agent's
/// request (GRANULAR pending → approve/deny).
///
/// Grant entities carry **metadata only** — never any crypto material
/// (`reEncryptedBlob`, `agentWrappedDek`, nonces). Those are produced
/// on-device at approval time and posted directly to the backend, never
/// surfaced back into a list/detail response.
library;

/// Lifecycle status of a grant. Mirrors the backend `GrantStatus` enum,
/// serialized as a camelCase string.
enum GrantStatus {
  /// Agent requested access; awaiting the owner's approval.
  pending,

  /// Approved and currently usable by the agent.
  active,

  /// Owner denied the request — never became usable.
  denied,

  /// Owner revoked a previously active grant.
  revoked,

  /// Expired by TTL or exhausted its query limit.
  expired;

  /// Maps the backend wire value (camelCase string or int ordinal) to a
  /// typed value. Unknown values fall back to [revoked] so a malformed
  /// payload fails closed (renders as no-access rather than active).
  static GrantStatus fromWire(Object? raw) {
    return switch (raw) {
      'pending' || 0 => GrantStatus.pending,
      'active' || 1 => GrantStatus.active,
      'denied' || 2 => GrantStatus.denied,
      'revoked' || 3 => GrantStatus.revoked,
      'expired' || 4 => GrantStatus.expired,
      _ => GrantStatus.revoked,
    };
  }
}

/// Access scope of a grant. Mirrors the backend `GrantMode` enum
/// (`Full = 1`, `Granular = 2`).
enum GrantScope {
  /// Agent can read every entry in the vault.
  full,

  /// Agent can read only the single granted entry.
  granular;

  static GrantScope fromWire(Object? raw) {
    return switch (raw) {
      'full' || 1 => GrantScope.full,
      _ => GrantScope.granular,
    };
  }
}

/// Domain representation of a single grant (list/detail shape).
///
/// All identifiers are opaque server-issued strings. No crypto material.
class Grant {
  const Grant({
    required this.id,
    required this.vaultId,
    required this.agentId,
    required this.status,
    required this.scope,
    required this.createdAt,
    this.agentName,
    this.entryId,
    this.entryLabel,
    this.reason,
    this.expiresAt,
    this.queryLimit,
    this.queryCount,
    this.approvedAt,
    this.approvedByName,
    this.revokedAt,
  });

  /// Stable, server-issued grant identifier.
  final String id;

  final String vaultId;
  final String agentId;

  /// Display name of the requesting agent, or `null` if unnamed.
  final String? agentName;

  final GrantStatus status;
  final GrantScope scope;

  /// Target entry id — `null` for FULL grants (which cover all entries).
  final String? entryId;

  /// Display label of the target entry, or `null` for FULL grants.
  final String? entryLabel;

  /// Agent-supplied justification shown to the owner. Required on every
  /// request per the security model, but tolerated as `null` here for
  /// resilience against older payloads.
  final String? reason;

  final DateTime createdAt;

  /// Absolute expiry timestamp (TTL grants), or `null` when the grant is
  /// limited by [queryLimit] instead, or unbounded.
  final DateTime? expiresAt;

  /// Maximum number of reads allowed (use-limited grants), or `null` when
  /// limited by [expiresAt] instead. Mutually exclusive with [expiresAt].
  final int? queryLimit;

  /// Number of reads consumed so far, when [queryLimit] applies.
  final int? queryCount;

  final DateTime? approvedAt;
  final String? approvedByName;
  final DateTime? revokedAt;
}
