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

/// Outcome recorded by the canonical backend `AuditLogListItem` contract.
enum AuditResult {
  succeeded,
  denied,
  failed,
  unknown;

  /// Accepts the numeric enum representation emitted by ASP.NET as well as
  /// string enum values used by fixtures and forward-compatible deployments.
  static AuditResult fromWire(Object? raw) {
    return switch (raw) {
      1 || 'succeeded' || 'Succeeded' => AuditResult.succeeded,
      2 || 'denied' || 'Denied' => AuditResult.denied,
      3 || 'failed' || 'Failed' => AuditResult.failed,
      _ => AuditResult.unknown,
    };
  }
}

/// Coarse grouping of audit events, used for the quick-filter chips and the
/// legend modal (color/icon families). Mirrors the security domains the
/// backend taxonomy splits into: credential access, grant lifecycle,
/// vault/entry CRUD, agent lifecycle, API keys, and org/account events.
enum AuditEventGroup {
  credentialAccess,
  grants,
  vaultEntry,
  agentLifecycle,
  apiKeys,
  orgAccount,
}

/// The catalogue of audit event types emitted by the backend. The wire
/// value is the dotted string the API returns (e.g. `credential.accessed`).
/// Unknown / future event types parse to [unknown] so a new backend event
/// never crashes the list — it simply renders with a neutral style.
enum AuditEventType {
  loginFailed('auth.login-failed', AuditEventGroup.orgAccount),
  grantRequested('grant.requested', AuditEventGroup.grants),
  grantCreated('grant.created', AuditEventGroup.grants),
  grantApproved('grant.approved', AuditEventGroup.grants),
  grantDenied('grant.denied', AuditEventGroup.grants),
  grantRevoked('grant.revoked', AuditEventGroup.grants),
  grantConsumed('grant.consumed', AuditEventGroup.grants),
  grantExpired('grant.expired', AuditEventGroup.grants),
  credentialAccessed('credential.accessed', AuditEventGroup.credentialAccess),
  credentialAccessDenied(
    'credential.access-denied',
    AuditEventGroup.credentialAccess,
  ),
  vaultCreated('vault.created', AuditEventGroup.vaultEntry),
  vaultUpdated('vault.updated', AuditEventGroup.vaultEntry),
  vaultDeleted('vault.deleted', AuditEventGroup.vaultEntry),
  vaultExported('vault.exported', AuditEventGroup.vaultEntry),
  entryCreated('entry.created', AuditEventGroup.vaultEntry),
  entryUpdated('entry.updated', AuditEventGroup.vaultEntry),
  entryDeleted('entry.deleted', AuditEventGroup.vaultEntry),
  agentEnrolled('agent.enrolled', AuditEventGroup.agentLifecycle),
  agentBlocked('agent.blocked', AuditEventGroup.agentLifecycle),
  agentReactivated('agent.reactivated', AuditEventGroup.agentLifecycle),
  agentDeleted('agent.deleted', AuditEventGroup.agentLifecycle),
  apikeyCreated('apikey.created', AuditEventGroup.apiKeys),
  apikeyActivated('apikey.activated', AuditEventGroup.apiKeys),
  apikeyRevoked('apikey.revoked', AuditEventGroup.apiKeys),
  apikeyDeleted('apikey.deleted', AuditEventGroup.apiKeys),
  orgCreated('org.created', AuditEventGroup.orgAccount),
  orgUpdated('org.updated', AuditEventGroup.orgAccount),
  userSignedUp('user.signed-up', AuditEventGroup.orgAccount),
  accountSetupCompleted('account.setup-completed', AuditEventGroup.orgAccount),
  accountRecoveryCompleted(
    'account.recovery-completed',
    AuditEventGroup.orgAccount,
  ),
  unknown('', AuditEventGroup.orgAccount);

  const AuditEventType(this.wire, this.group);

  /// The backend wire string for this event type.
  final String wire;

  /// The coarse [AuditEventGroup] this event belongs to.
  final AuditEventGroup group;

  /// Parses a backend event-type string into a typed value, falling back
  /// to [unknown] for anything unrecognized.
  static AuditEventType fromWire(Object? raw) {
    if (raw is! String) return AuditEventType.unknown;
    for (final type in AuditEventType.values) {
      if (type.wire == raw) return type;
    }
    return AuditEventType.unknown;
  }

  /// Every real (non-[unknown]) event type, in declaration order.
  static List<AuditEventType> get known =>
      values.where((t) => t != AuditEventType.unknown).toList(growable: false);

  /// The event types that belong to [group] (excludes [unknown]).
  static List<AuditEventType> inGroup(AuditEventGroup group) =>
      known.where((t) => t.group == group).toList(growable: false);

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

  /// Groups available as quick-filter chips on the vault-scoped Logs tab —
  /// the security domains that can occur within a single vault.
  static const List<AuditEventGroup> vaultGroups = [
    AuditEventGroup.credentialAccess,
    AuditEventGroup.grants,
    AuditEventGroup.vaultEntry,
    AuditEventGroup.agentLifecycle,
  ];

  /// Groups available as quick-filter chips on the org-wide Logs screen —
  /// the full taxonomy.
  static const List<AuditEventGroup> orgGroups = AuditEventGroup.values;
}

/// A single audit log entry as returned by the backend list endpoints.
class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.eventType,
    required this.rawEventType,
    required this.actorType,
    required this.createdAt,
    DateTime? occurredAt,
    this.result = AuditResult.unknown,
    this.userId,
    this.agentId,
    this.agentName,
    this.actorName,
    this.vaultId,
    this.entryId,
    this.entryLabel,
    this.agentReason,
    this.resolvedObjectName,
    this.resolvedVaultName,
    this.localPresentationOnly = false,
    this.metadata = const {},
  }) : occurredAt = occurredAt ?? createdAt;

  final String id;

  /// Typed event type ([AuditEventType.unknown] for unrecognized values).
  final AuditEventType eventType;

  /// The original backend event-type string — preserved so an [unknown]
  /// event can still be displayed verbatim.
  final String rawEventType;

  final AuditActorType actorType;

  final AuditResult result;

  /// Timestamp carried by the source event and used for the audit timeline.
  final DateTime occurredAt;

  /// Timestamp when the Audit module persisted the record (local time).
  final DateTime createdAt;

  /// Acting user id (when [actorType] is [AuditActorType.user]).
  final String? userId;

  /// Acting / target agent id (when an agent is involved).
  final String? agentId;

  /// Human-readable agent name, denormalized server-side at write time.
  /// Preferred over a client-side id→name lookup when present.
  final String? agentName;

  /// Human-readable actor name, denormalized server-side (the acting user
  /// or agent). Preferred over a client-side lookup when present.
  final String? actorName;

  final String? vaultId;

  /// The entry this event is scoped to, or `null` for vault-/org-level
  /// events.
  final String? entryId;

  /// Human-readable entry label, denormalized server-side at write time.
  final String? entryLabel;

  /// Free-text reason the agent supplied when requesting access.
  final String? agentReason;

  /// Runtime-only display resolved from unlocked local projections.
  final String? resolvedObjectName;

  /// Runtime-only Vault name resolved from unlocked local state.
  final String? resolvedVaultName;

  /// Whether presentation fields must come exclusively from unlocked local
  /// projections. Vault-scoped logs set this to avoid trusting legacy server
  /// labels while org-wide audit keeps its existing non-secret presentation.
  final bool localPresentationOnly;

  /// Non-sensitive contextual key/values (grant id, method, ip, device…).
  final Map<String, String> metadata;
}
