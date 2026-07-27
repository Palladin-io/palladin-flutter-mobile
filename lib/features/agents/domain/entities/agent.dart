/// Domain entities for the agents feature.
///
/// An "agent" is an external automation (CLI tool, AI assistant) that
/// enrolls itself against the organization. Enrolled agents start in the
/// [AgentStatus.pending] state and must be approved by a human before
/// they can access vaults.
library;

/// Lifecycle status of an agent.
///
/// Mirrors the backend's integer `status` field — `1` / `2` / `3`.
enum AgentStatus {
  /// The agent has enrolled but is awaiting human approval — it cannot
  /// access the organization yet.
  pending,

  /// The agent is approved and can access organization vaults.
  active,

  /// The agent has been deactivated and has lost all access. It can be
  /// re-activated later — agents are never permanently deleted.
  deactivated,
}

extension AgentStatusExtension on AgentStatus {
  /// Maps the backend's integer `status` to the typed enum.
  ///
  /// Unknown values fall back to [AgentStatus.deactivated] — failing
  /// closed keeps a malformed payload from rendering an agent as active.
  static AgentStatus fromWire(int value) {
    return switch (value) {
      1 => AgentStatus.pending,
      2 => AgentStatus.active,
      _ => AgentStatus.deactivated,
    };
  }
}

/// Domain representation of a single agent.
///
/// Carries metadata only — no secret material. The agent's public key
/// is identified by its [publicKeyPrefix] / [publicKeySuffix] for display
/// purposes.
class Agent {
  const Agent({
    required this.agentId,
    required this.name,
    required this.status,
    required this.publicKeySuffix,
    required this.createdAt,
    this.type,
    this.iconKey,
    this.iconColor,
    this.publicKeyPrefix = '',
    this.publicKey = '',
    this.recipientKeyVersion = 1,
    this.enrolledAt,
    this.enrolledByName,
    this.deactivatedAt,
    this.deactivatedByName,
    this.description,
    this.lastAccessAt,
    this.lastIp,
    this.lastHostname,
  });

  /// Stable, server-issued identifier.
  final String agentId;

  /// User-supplied display name for the agent, or `null` if it has not
  /// been named yet.
  final String? name;

  /// Agent classification set at approval time — one of `openClaw`,
  /// `claudeCode`, `hermes`, `other` — or `null` when not yet set.
  final String? type;

  /// Material icon name chosen for the agent at approval time, or `null`
  /// when no icon has been assigned.
  final String? iconKey;

  /// Hex color string (e.g. `"#10B981"`) for the icon tint, chosen by the
  /// operator. When `null`, [agentIconColor] is used as the default.
  final String? iconColor;

  /// Current lifecycle status — see [AgentStatus].
  final AgentStatus status;

  /// First 8 characters of the agent's public key. Combined with
  /// [publicKeySuffix] to render a `{prefix}•••{suffix}` identifier.
  final String publicKeyPrefix;

  /// Full public key of the agent. Public material — safe to display;
  /// never confused with private/secret key material.
  final String publicKey;

  /// Version of the current Agent X25519 recipient key.
  final int recipientKeyVersion;

  /// Short suffix of the agent's public key, shown in monospace so an
  /// operator can visually identify the enrolled key.
  final String publicKeySuffix;

  /// When the agent first connected / enrolled.
  final DateTime createdAt;

  /// When the agent was approved, or `null` while still pending.
  final DateTime? enrolledAt;

  /// Display name of the human who approved the agent, or `null`.
  final String? enrolledByName;

  /// When the agent was deactivated, or `null` if it is not deactivated.
  final DateTime? deactivatedAt;

  /// Display name of the human who deactivated the agent, or `null`.
  final String? deactivatedByName;

  /// Free-text description of the agent's purpose, or `null`.
  final String? description;

  /// When the agent last successfully accessed the organization (e.g. opened
  /// a vault entry). `null` when the agent has never made a request — newly
  /// enrolled agents will not have a value here until their first call.
  final DateTime? lastAccessAt;

  /// Last known IP address the agent connected from, or `null` when the
  /// agent has not been seen yet. Public metadata — safe to display.
  final String? lastIp;

  /// Last known hostname the agent connected from, or `null` when not
  /// reported by the agent. Public metadata — safe to display.
  final String? lastHostname;

  bool get isPending => status == AgentStatus.pending;

  bool get isActive => status == AgentStatus.active;

  bool get isDeactivated => status == AgentStatus.deactivated;

  /// Abbreviated public-key identifier in `{prefix}•••{suffix}` form.
  ///
  /// Falls back to just the suffix when no prefix is available (older
  /// payloads), or `—` when neither part is present.
  String get publicKeyDisplay {
    final prefix = publicKeyPrefix.trim();
    final suffix = publicKeySuffix.trim();
    if (prefix.isNotEmpty && suffix.isNotEmpty) return '$prefix•••$suffix';
    if (suffix.isNotEmpty) return suffix;
    if (prefix.isNotEmpty) return prefix;
    return '—';
  }
}
