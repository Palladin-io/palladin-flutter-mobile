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

import 'grant_method.dart';

export 'grant_method.dart';

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

  /// Expired by TTL.
  expired,

  /// Exhausted its query limit (use-limited grants).
  consumed;

  /// Maps the backend wire value (camelCase string or int ordinal) to a
  /// typed value. Unknown values fall back to [revoked] so a malformed
  /// payload fails closed (renders as no-access rather than active).
  static GrantStatus fromWire(Object? raw) {
    return switch (raw) {
      'pending' || 1 => GrantStatus.pending,
      'active' || 2 => GrantStatus.active,
      'expired' || 3 => GrantStatus.expired,
      'revoked' || 4 => GrantStatus.revoked,
      'consumed' || 5 => GrantStatus.consumed,
      'denied' || 6 => GrantStatus.denied,
      _ => GrantStatus.revoked,
    };
  }

  /// A grant in a finished state (not active, not awaiting a decision) —
  /// mirrors the web `isTerminal` helper. Used to decide whether to show the
  /// "already active" footer when no action is available.
  bool get isTerminal =>
      this != GrantStatus.active && this != GrantStatus.pending;
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
      'full' || 2 => GrantScope.full,
      'granular' || 1 => GrantScope.granular,
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
    this.agentId,
    required this.status,
    required this.scope,
    required this.createdAt,
    this.agentName,
    this.agentIconKey,
    this.agentPublicKey,
    this.recipientAgentKeyVersion,
    this.entryScopes = const [],
    this.vaultName,
    this.entryId,
    this.entryLabel,
    this.reason,
    this.methods = const [],
    this.expiresAt,
    this.queryLimit,
    this.queryCount,
    this.approvedAt,
    this.approvedByName,
    this.revokedAt,
    this.createdBy,
    this.createdByName,
    this.revokedBy,
    this.revokedByName,
    this.deniedBy,
    this.deniedByName,
    this.denyReason,
    this.canRevoke = false,
    this.canGrantAgain = false,
    this.activeCoveringGrantIds = const [],
  });

  /// Stable, server-issued grant identifier.
  final String id;

  final String vaultId;
  final String? agentId;

  /// Display name of the requesting agent, or `null` if unnamed.
  final String? agentName;

  /// Agent's chosen avatar — a Material glyph name or an uploaded URL. Lets
  /// the org-grant card render the agent's real avatar. `null` → initials.
  final String? agentIconKey;

  /// Agent's base64 X25519 public key — needed to seal a DEK when re-granting
  /// ("Grant again"). Public by design (it can only seal *to* the agent).
  final String? agentPublicKey;

  /// Current public recipient-key version used for a refreshed envelope.
  final int? recipientAgentKeyVersion;

  /// Durable field scope and current envelope counters. Contains no secrets.
  final List<GrantEntryScope> entryScopes;

  /// Display name of the owning vault (org-wide listing only).
  final String? vaultName;

  final GrantStatus status;
  final GrantScope scope;

  /// Target entry id — `null` for FULL grants (which cover all entries).
  final String? entryId;

  /// Display label of the target entry, or `null` for FULL grants.
  final String? entryLabel;

  /// Methods the grant permits. Empty when the backend predates the
  /// feature; the card hides the badges in that case.
  final List<GrantMethod> methods;

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

  /// Stable id of the Member who created or approved the grant.
  final String? createdBy;

  /// Actor who created the grant (proactive grant / approval). Org listing.
  final String? createdByName;

  /// Stable id of the Member who revoked the grant, when user-initiated.
  final String? revokedBy;

  /// Actor who revoked the grant, when [status] is revoked.
  final String? revokedByName;

  /// Stable id of the Member who denied the request.
  final String? deniedBy;

  /// Actor who denied the grant, when [status] is denied.
  final String? deniedByName;

  /// Owner-supplied reason recorded at deny time.
  final String? denyReason;

  /// Per-grant action availability computed by the backend. The UI renders
  /// actions strictly from these flags, never inferring from [status] — so no
  /// action is wrongly offered (e.g. revoking an already-expired grant).
  final bool canRevoke;
  final bool canGrantAgain;

  /// Newer active grants that currently cover the same access. Empty when
  /// re-granting is blocked for another reason, such as an inactive Agent.
  final List<String> activeCoveringGrantIds;
}

/// One Entry covered by a grant, with ciphertext-only refresh metadata.
class GrantEntryScope {
  const GrantEntryScope({
    required this.entryId,
    required this.fieldIds,
    this.grantEnvelopeRevision,
    this.entryRevision,
    this.grantKeyVersion,
    this.memberKeyGeneration,
    this.recipientAgentKeyVersion,
    this.agentKeyFingerprint,
  });

  final String entryId;
  final List<String> fieldIds;
  final String? grantEnvelopeRevision;
  final String? entryRevision;
  final int? grantKeyVersion;
  final int? memberKeyGeneration;
  final int? recipientAgentKeyVersion;
  final String? agentKeyFingerprint;
}
