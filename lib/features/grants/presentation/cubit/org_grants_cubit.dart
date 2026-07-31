import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/grant.dart';
import '../../domain/exceptions/grants_exceptions.dart';
import '../../domain/repositories/grants_repository.dart';
import 'org_grants_state.dart';

export 'org_grants_state.dart';

/// Drives the Approvals "history" feed — every org-wide grant except pending
/// (those are handled by the Pending segment). Loads once, then filters
/// (status multi-select + search) client-side. Supports inline revoke.
class OrgGrantsCubit extends Cubit<OrgGrantsState> {
  OrgGrantsCubit({required this.repository}) : super(const OrgGrantsState());

  final GrantsRepository repository;

  static const _pageSize = 100;

  // Context filter: when set, the feed is scoped server-side to a single
  // agent / vault / entry (the detail-screen Agents/Grants tabs). Stored so revoke→reload keeps the
  // same scope. All null = the Approvals org-wide history feed.
  String? _agentId;
  String? _vaultId;
  String? _entryId;

  /// Loads the grants feed (newest-first). With no context filter this is the Approvals history
  /// feed and pending grants are dropped (they live in the Pending segment). With a context filter
  /// (agent/vault/entry detail tab) ALL statuses are kept — mirrors the web OrgGrantsPanel.
  Future<void> load({String? agentId, String? vaultId, String? entryId}) async {
    _agentId = agentId;
    _vaultId = vaultId;
    _entryId = entryId;
    final scoped = agentId != null || vaultId != null || entryId != null;
    emit(state.copyWith(status: OrgGrantsStatus.loading, clearError: true));
    try {
      final page = await repository.listOrgGrants(
        agentId: agentId,
        vaultId: vaultId,
        entryId: entryId,
        pageSize: _pageSize,
      );
      final grants = scoped
          ? page.grants
          : page.grants
                .where((g) => g.status != GrantStatus.pending)
                .toList(growable: false);
      AppLogger.i('Grants', 'Loaded ${grants.length} org grants');
      emit(state.copyWith(status: OrgGrantsStatus.loaded, grants: grants));
    } on GrantsException catch (e) {
      AppLogger.w('Grants', 'Org grant load failed: ${e.kind.name}');
      emit(state.copyWith(status: OrgGrantsStatus.error, error: e.kind));
    } catch (e, s) {
      AppLogger.e(
        'Grants',
        'Org grant load failed unexpectedly',
        error: e,
        stackTrace: s,
      );
      emit(
        state.copyWith(
          status: OrgGrantsStatus.error,
          error: GrantsErrorKind.unknown,
        ),
      );
    }
  }

  /// Reloads keeping the current context scope (agent/vault/entry). Use after a mutation that
  /// changes the feed (revoke, re-grant) so a scoped tab stays scoped.
  Future<void> reload() =>
      load(agentId: _agentId, vaultId: _vaultId, entryId: _entryId);

  /// Toggles a status in the client-side filter (no refetch).
  void toggleStatus(GrantStatus status) {
    final next = Set<GrantStatus>.from(state.statusFilter);
    if (!next.remove(status)) next.add(status);
    emit(state.copyWith(statusFilter: next));
  }

  /// Clears the status filter.
  void clearStatusFilter() => emit(state.copyWith(statusFilter: const {}));

  /// Updates the search query (no refetch).
  void search(String query) => emit(state.copyWith(query: query));

  /// Revokes a grant then reloads so its status reflects the change.
  Future<void> revokeGrant(String vaultId, String grantId) async {
    emit(state.copyWith(revokingGrantId: grantId, clearMutationError: true));
    try {
      await repository.revokeGrant(vaultId, grantId);
      // Reload within the same scope so a context-filtered tab stays filtered.
      await reload();
      emit(state.copyWith(clearRevokingGrantId: true));
    } on GrantsException catch (e) {
      AppLogger.w('Grants', 'revokeGrant failed: ${e.kind.name}');
      emit(state.copyWith(mutationError: e.kind, clearRevokingGrantId: true));
    } catch (e, s) {
      AppLogger.e(
        'Grants',
        'revokeGrant failed unexpectedly',
        error: e,
        stackTrace: s,
      );
      emit(
        state.copyWith(
          mutationError: GrantsErrorKind.unknown,
          clearRevokingGrantId: true,
        ),
      );
    }
  }

  /// Clears the transient mutation error after the UI shows its snackbar.
  void acknowledgeMutationError() {
    if (state.mutationError == null) return;
    emit(state.copyWith(clearMutationError: true));
  }
}
