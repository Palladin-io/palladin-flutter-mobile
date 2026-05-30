import '../entities/agent.dart';

/// Domain contract for agent management.
///
/// Implemented in the data layer by `AgentsRepositoryImpl`. All failures
/// surface as `AgentsException` with a typed `AgentsErrorKind` so the
/// presentation layer can render localized error messages without
/// leaking transport details.
abstract interface class AgentsRepository {
  /// Returns every agent (pending, active and deactivated) for the
  /// organization.
  Future<List<Agent>> listAgents();

  /// Fetches a single agent by id.
  Future<Agent> getAgent(String agentId);

  /// Approves a pending agent, granting it access to the organization.
  ///
  /// Optionally sets the agent's [name], [type] and [iconKey] at
  /// approval time. Passing `null` for any of them leaves the server
  /// default unchanged.
  Future<void> approveAgent(
    String agentId, {
    String? name,
    String? type,
    String? iconKey,
  });

  /// Deactivates an active agent — it immediately loses all access.
  Future<void> deactivateAgent(String agentId);

  /// Re-activates a previously deactivated agent.
  Future<void> reactivateAgent(String agentId);

  /// Updates the mutable metadata of an agent.
  ///
  /// Passing `null` for any field leaves it unchanged on the server.
  Future<void> updateAgent(
    String agentId, {
    String? name,
    String? description,
    String? iconKey,
    String? iconColor,
  });
}
