/// Domain entities for the audit feature.
///
/// An audit log entry is an immutable, append-only record of a security-
/// relevant action (credential access, grant lifecycle, entry CRUD…).
/// Entries carry **metadata only** — never plaintext credentials,
/// ciphertext, keys or nonces. The backend strips all secrets before the
/// row is ever persisted, so nothing here is sensitive to display.
library;

/// Who performed the action recorded by an audit entry. Mirrors the
/// backend `AuditActorType` enum (serialized as an int ordinal or a
/// PascalCase string).
enum AuditActorType {
  user,
  agent,
  system;

  /// Maps the backend wire value (int ordinal or string) to a typed
  /// value. Unknown values fall back to [system] (an automatic actor).
  static AuditActorType fromWire(Object? raw) {
    return switch (raw) {
      1 || 'user' || 'User' => AuditActorType.user,
      2 || 'agent' || 'Agent' => AuditActorType.agent,
      3 || 'system' || 'System' => AuditActorType.system,
      _ => AuditActorType.system,
    };
  }
}

/// The catalogue of audit event types emitted by the backend. The wire
/// value is the dotted string the API returns (e.g. `credential.accessed`).
/// Unknown / future event types parse to [unknown] so a new backend event
/// never crashes the list — it simply renders with a neutral style.
enum AuditEventType {
  grantCreated('grant.created'),
  grantRequested('grant.requested'),
  grantApproved('grant.approved'),
  grantDenied('grant.denied'),
  grantRevoked('grant.revoked'),
  grantConsumed('grant.consumed'),
  grantExpired('grant.expired'),
  credentialAccessed('credential.accessed'),
  credentialAccessDenied('credential.access-denied'),
  agentEnrolled('agent.enrolled'),
  agentBlocked('agent.blocked'),
  agentReactivated('agent.reactivated'),
  agentDeleted('agent.deleted'),
  vaultCreated('vault.created'),
  vaultUpdated('vault.updated'),
  vaultDeleted('vault.deleted'),
  entryCreated('entry.created'),
  entryUpdated('entry.updated'),
  entryDeleted('entry.deleted'),
  unknown('');

  const AuditEventType(this.wire);

  /// The backend wire string for this event type.
  final String wire;

  /// Parses a backend event-type string into a typed value, falling back
  /// to [unknown] for anything unrecognized.
  static AuditEventType fromWire(Object? raw) {
    if (raw is! String) return AuditEventType.unknown;
    for (final type in AuditEventType.values) {
      if (type.wire == raw) return type;
    }
    return AuditEventType.unknown;
  }

  /// The subset of event types that can be scoped to a single entry — the
  /// filter chips shown on the entry-detail Logs tab. Order matches the
  /// prototype's 8-checkbox panel.
  static const List<AuditEventType> entryRelevant = [
    AuditEventType.credentialAccessed,
    AuditEventType.credentialAccessDenied,
    AuditEventType.entryCreated,
    AuditEventType.entryUpdated,
    AuditEventType.entryDeleted,
    AuditEventType.grantCreated,
    AuditEventType.grantApproved,
    AuditEventType.grantRevoked,
  ];
}

/// A single audit log entry as returned by the backend list endpoints.
class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.eventType,
    required this.rawEventType,
    required this.actorType,
    required this.createdAt,
    this.userId,
    this.agentId,
    this.vaultId,
    this.entryId,
    this.entryLabel,
    this.agentReason,
    this.metadata = const {},
  });

  final String id;

  /// Typed event type ([AuditEventType.unknown] for unrecognized values).
  final AuditEventType eventType;

  /// The original backend event-type string — preserved so an [unknown]
  /// event can still be displayed verbatim.
  final String rawEventType;

  final AuditActorType actorType;

  /// When the action occurred (local time).
  final DateTime createdAt;

  /// Acting user id (when [actorType] is [AuditActorType.user]).
  final String? userId;

  /// Acting / target agent id (when an agent is involved).
  final String? agentId;

  final String? vaultId;

  /// The entry this event is scoped to, or `null` for vault-/org-level
  /// events.
  final String? entryId;

  /// Human-readable entry label, denormalized server-side at write time.
  final String? entryLabel;

  /// Free-text reason the agent supplied when requesting access.
  final String? agentReason;

  /// Non-sensitive contextual key/values (grant id, method, ip, device…).
  final Map<String, String> metadata;
}
