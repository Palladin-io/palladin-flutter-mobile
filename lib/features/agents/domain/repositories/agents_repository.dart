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
  Future<void> approveAgent(String agentId);

  /// Deactivates an active agent — it immediately loses all access.
  Future<void> deactivateAgent(String agentId);

  /// Re-activates a previously deactivated agent.
  Future<void> reactivateAgent(String agentId);

  /// Updates the mutable metadata of an agent.
  ///
  /// Only [name] and [description] are editable. Passing `null` for
  /// either leaves that field unchanged.
  Future<void> updateAgent(
    String agentId, {
    String? name,
    String? description,
  });
}
