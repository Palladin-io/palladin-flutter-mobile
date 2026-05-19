import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/exceptions/agents_exceptions.dart';
import '../../domain/repositories/agents_repository.dart';
import 'agents_state.dart';

export 'agents_state.dart';

/// Drives the agents feature — the list screen ([AgentsPage]), the
/// detail screen ([AgentDetailPage]) and the edit screen
/// ([AgentEditPage]).
///
/// Each screen mounts its own cubit instance (registered as a factory in
/// DI), so stale loading / error state never leaks across visits. The
/// detail and edit screens resolve their agent by id from the loaded
/// list.
class AgentsCubit extends Cubit<AgentsState> {
  AgentsCubit({required this.repository}) : super(const AgentsState());

  final AgentsRepository repository;

  /// Fetches the agents list — called once on screen mount.
  Future<void> load() async {
    AppLogger.d('Agents', 'Loading agents');
    emit(state.copyWith(status: AgentsStatus.loading, clearError: true));
    try {
      final agents = await repository.listAgents();
      AppLogger.i('Agents', 'Loaded ${agents.length} agents');
      emit(state.copyWith(status: AgentsStatus.loaded, agents: agents));
    } on AgentsException catch (e) {
      AppLogger.w('Agents', 'Agent load failed: ${e.kind.name}');
      emit(state.copyWith(status: AgentsStatus.error, error: e.kind));
    } catch (e, s) {
      AppLogger.e('Agents', 'Agent load failed unexpectedly',
          error: e, stackTrace: s);
      emit(state.copyWith(
        status: AgentsStatus.error,
        error: AgentsErrorKind.unknown,
      ));
    }
  }

  /// Approves a pending agent, then refreshes the list.
  Future<void> approveAgent(String agentId) =>
      _runMutation(agentId, () => repository.approveAgent(agentId));

  /// Deactivates an active agent, then refreshes the list.
  Future<void> deactivateAgent(String agentId) =>
      _runMutation(agentId, () => repository.deactivateAgent(agentId));

  /// Re-activates a deactivated agent, then refreshes the list.
  Future<void> reactivateAgent(String agentId) =>
      _runMutation(agentId, () => repository.reactivateAgent(agentId));

  /// Updates an agent's name and/or description, then refreshes the list.
  ///
  /// Both values are trimmed before hitting the API. Pass `null` to
  /// leave a field unchanged.
  Future<void> updateAgent(
    String agentId, {
    String? name,
    String? description,
  }) {
    return _runMutation(
      agentId,
      () => repository.updateAgent(
        agentId,
        name: name?.trim(),
        description: description?.trim(),
      ),
    );
  }

  /// Shared driver for every agent mutation.
  ///
  /// Marks [agentId] as mutating, runs [action], then reloads the list
  /// on success. On failure the error is surfaced as a transient
  /// [AgentsState.mutationError] — the list and detail card stay visible
  /// so the user does not lose sight of the agent.
  Future<void> _runMutation(
    String agentId,
    Future<void> Function() action,
  ) async {
    emit(state.copyWith(
      mutatingAgentId: agentId,
      clearMutationError: true,
    ));
    try {
      await action();
      final agents = await repository.listAgents();
      emit(state.copyWith(
        status: AgentsStatus.loaded,
        agents: agents,
        clearMutatingAgentId: true,
      ));
    } on AgentsException catch (e) {
      AppLogger.w('Agents', 'Agent mutation failed: ${e.kind.name}');
      emit(state.copyWith(
        mutationError: e.kind,
        clearMutatingAgentId: true,
      ));
    } catch (e, s) {
      AppLogger.e('Agents', 'Agent mutation failed unexpectedly',
          error: e, stackTrace: s);
      emit(state.copyWith(
        mutationError: AgentsErrorKind.unknown,
        clearMutatingAgentId: true,
      ));
    }
  }

  /// Clears the transient [AgentsState.mutationError] after the UI has
  /// shown its snackbar — keeps it from re-firing on the next rebuild.
  void acknowledgeMutationError() {
    if (state.mutationError == null) return;
    emit(state.copyWith(clearMutationError: true));
  }
}
