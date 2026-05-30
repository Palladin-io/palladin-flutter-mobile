import 'package:flutter/painting.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/agent.dart';
import '../../domain/exceptions/agents_exceptions.dart';
import '../../domain/repositories/agents_repository.dart';
import 'agents_state.dart';

export 'agents_state.dart';

/// Drives the agents feature — the list screen ([AgentsPage]) and the
/// detail screen ([AgentDetailPage]). Editing happens inline inside the
/// detail screen's Details tab.
///
/// Registered as a `lazySingleton` in DI: both screens share one instance
/// (via `BlocProvider.value`) so a mutation on the detail screen (approve,
/// deactivate, icon save) is immediately reflected in the list without a
/// reload. The detail screen resolves its agent by id from the loaded list.
///
/// Because the instance lives for the whole app lifecycle it is never
/// `close()`-d — call [reset] on logout / organization switch to drop the
/// previous session's agents so they never leak across accounts.
class AgentsCubit extends Cubit<AgentsState> {
  AgentsCubit({required this.repository}) : super(const AgentsState());

  final AgentsRepository repository;

  /// Drops all loaded agents and transient error / mutation state back to
  /// the initial state. Call on logout or organization switch so the next
  /// session starts clean — the singleton instance is reused, not recreated.
  void reset() => emit(const AgentsState());

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
  ///
  /// Optionally assigns the agent's [name], [type] and [iconKey] at
  /// approval time. [name] is trimmed; an empty name is sent as `null`
  /// so the server keeps its default.
  Future<void> approveAgent(
    String agentId, {
    String? name,
    String? type,
    String? iconKey,
  }) {
    final trimmedName = name?.trim();
    return _runMutation(
      agentId,
      () => repository.approveAgent(
        agentId,
        name: (trimmedName == null || trimmedName.isEmpty)
            ? null
            : trimmedName,
        type: type,
        iconKey: iconKey,
      ),
    );
  }

  /// Deactivates an active agent, then refreshes the list.
  Future<void> deactivateAgent(String agentId) =>
      _runMutation(agentId, () => repository.deactivateAgent(agentId));

  /// Re-activates a deactivated agent, then refreshes the list.
  Future<void> reactivateAgent(String agentId) =>
      _runMutation(agentId, () => repository.reactivateAgent(agentId));

  /// Updates an agent's name, description and/or icon.
  ///
  /// Unlike the other mutations, this uses [AgentsRepository.getAgent] after
  /// a successful PATCH to fetch a single fresh agent rather than
  /// [listAgents] — the list endpoint may omit `iconKey` and other detail
  /// fields, causing the avatar to revert after save.
  ///
  /// [iconKey] is what gets sent to the API. [iconKeyDisplay] is the value
  /// shown in the avatar optimistically — it may differ when the S3 upload
  /// failed and we have a local `file://` path that can't go to the backend.
  /// When [iconKeyDisplay] is omitted it falls back to [iconKey].
  Future<void> updateAgent(
    String agentId, {
    String? name,
    String? description,
    String? iconKey,
    String? iconKeyDisplay,
    String? iconColor,
  }) async {
    AppLogger.d('Agents', 'updateAgent: $agentId');
    emit(state.copyWith(mutatingAgentId: agentId, clearMutationError: true));
    try {
      await repository.updateAgent(
        agentId,
        name: name?.trim(),
        description: description?.trim(),
        iconKey: iconKey,
        iconColor: iconColor,
      );
      // S3 reuses the same object key on re-upload, so the canonical
      // public URL is byte-for-byte identical across uploads. Evict any
      // cached copy so list / detail avatars refetch the new bytes
      // instead of serving the stale image from the [imageCache].
      _evictIconCache(iconKey);
      _evictIconCache(iconKeyDisplay);
      final fresh = await repository.getAgent(agentId);
      final effectiveIconKey = iconKeyDisplay ?? iconKey ?? fresh.iconKey;
      final needsOverride = iconColor != null ||
          (effectiveIconKey != null && effectiveIconKey != fresh.iconKey);
      final withColor = needsOverride
          ? Agent(
              agentId: fresh.agentId,
              name: fresh.name,
              status: fresh.status,
              publicKeySuffix: fresh.publicKeySuffix,
              createdAt: fresh.createdAt,
              type: fresh.type,
              iconKey: effectiveIconKey,
              iconColor: iconColor ?? fresh.iconColor,
              publicKeyPrefix: fresh.publicKeyPrefix,
              publicKey: fresh.publicKey,
              enrolledAt: fresh.enrolledAt,
              enrolledByName: fresh.enrolledByName,
              deactivatedAt: fresh.deactivatedAt,
              deactivatedByName: fresh.deactivatedByName,
              description: fresh.description,
            )
          : fresh;
      final updated = state.agents
          .map((a) => a.agentId == agentId ? withColor : a)
          .toList(growable: false);
      emit(state.copyWith(
        status: AgentsStatus.loaded,
        agents: updated,
        clearMutatingAgentId: true,
      ));
    } on AgentsException catch (e) {
      AppLogger.w('Agents', 'updateAgent failed: ${e.kind.name}');
      emit(state.copyWith(
        mutationError: e.kind,
        clearMutatingAgentId: true,
      ));
    } catch (e, s) {
      AppLogger.e('Agents', 'updateAgent failed unexpectedly',
          error: e, stackTrace: s);
      emit(state.copyWith(
        mutationError: AgentsErrorKind.unknown,
        clearMutatingAgentId: true,
      ));
    }
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

  /// Evicts both the canonical and any `?v=`-suffixed variant of [url] from
  /// the global image cache so any rendered [NetworkImage] reloads fresh
  /// bytes after an S3 re-upload to the same object key.
  ///
  /// Wrapped in `try/catch` because [PaintingBinding.instance] is unavailable
  /// in pure-Dart test environments that do not call
  /// `WidgetsFlutterBinding.ensureInitialized()` — eviction is a soft
  /// optimization, never load-bearing for correctness.
  void _evictIconCache(String? url) {
    if (url == null || url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) return;
    try {
      final cache = PaintingBinding.instance.imageCache;
      cache.evict(NetworkImage(url));
      final q = url.indexOf('?');
      if (q > 0) {
        cache.evict(NetworkImage(url.substring(0, q)));
      }
    } catch (_) {
      // PaintingBinding not initialised — running outside a widget tree.
    }
  }
}
