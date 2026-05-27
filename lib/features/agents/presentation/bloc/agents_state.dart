import '../../domain/entities/agent.dart';
import '../../domain/exceptions/agents_exceptions.dart';

/// Loading status of the agents list.
enum AgentsStatus { initial, loading, loaded, error }

/// Immutable state for the agents feature.
///
/// Drives the list page ([AgentsPage]) and the detail page
/// ([AgentDetailPage]) — the detail page resolves its agent from
/// [agents] by id so every surface always agrees (e.g. an approve on
/// the detail page is reflected in the list without a separate
/// refetch).
class AgentsState {
  const AgentsState({
    this.status = AgentsStatus.initial,
    this.agents = const [],
    this.error,
    this.mutationError,
    this.mutatingAgentId,
  });

  /// Load status of the list.
  final AgentsStatus status;

  /// All agents (pending, active and deactivated) for the organization.
  final List<Agent> agents;

  /// Set when the initial list load failed — drives the full-screen
  /// error state.
  final AgentsErrorKind? error;

  /// Transient error from an approve / deactivate / reactivate / update
  /// mutation. Unlike [error] this does *not* replace the screen — the
  /// UI shows it as a snackbar so the agent card stays visible, then
  /// calls [AgentsCubit.acknowledgeMutationError] to clear it.
  final AgentsErrorKind? mutationError;

  /// Id of the agent currently being mutated (approve / deactivate /
  /// reactivate / update), or `null` when no mutation is in flight —
  /// lets the UI disable the relevant button and show a spinner.
  final String? mutatingAgentId;

  /// Number of agents in the [AgentStatus.active] state.
  int get activeCount => agents.where((a) => a.isActive).length;

  /// Resolves a single agent by id, or `null` if it is not in the list.
  Agent? agentById(String agentId) {
    for (final agent in agents) {
      if (agent.agentId == agentId) return agent;
    }
    return null;
  }

  AgentsState copyWith({
    AgentsStatus? status,
    List<Agent>? agents,
    AgentsErrorKind? error,
    bool clearError = false,
    AgentsErrorKind? mutationError,
    bool clearMutationError = false,
    String? mutatingAgentId,
    bool clearMutatingAgentId = false,
  }) {
    return AgentsState(
      status: status ?? this.status,
      agents: agents ?? this.agents,
      error: clearError ? null : (error ?? this.error),
      mutationError:
          clearMutationError ? null : (mutationError ?? this.mutationError),
      mutatingAgentId: clearMutatingAgentId
          ? null
          : (mutatingAgentId ?? this.mutatingAgentId),
    );
  }
}
