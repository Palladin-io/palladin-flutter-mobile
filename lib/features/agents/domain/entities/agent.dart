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
/// is identified by its [publicKeySuffix] for display purposes.
class Agent {
  const Agent({
    required this.agentId,
    required this.name,
    required this.status,
    required this.publicKeySuffix,
    required this.createdAt,
    this.enrolledAt,
    this.enrolledByName,
    this.deactivatedAt,
    this.deactivatedByName,
    this.description,
  });

  /// Stable, server-issued identifier.
  final String agentId;

  /// User-supplied display name for the agent, or `null` if it has not
  /// been named yet.
  final String? name;

  /// Current lifecycle status — see [AgentStatus].
  final AgentStatus status;

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

  bool get isPending => status == AgentStatus.pending;

  bool get isActive => status == AgentStatus.active;

  bool get isDeactivated => status == AgentStatus.deactivated;
}
