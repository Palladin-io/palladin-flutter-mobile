import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/exceptions/grants_exceptions.dart';
import '../../domain/repositories/grants_repository.dart';
import 'grants_list_state.dart';

export 'grants_list_state.dart';

/// Drives the grant-management list screen for a single vault.
///
/// Factory-scoped per page mount (see DI) so filter/pagination state never
/// leaks across vaults. Supports status/agent filtering and cursor-based
/// "load more" pagination, plus inline revoke.
class GrantsListCubit extends Cubit<GrantsListState> {
  GrantsListCubit({required this.repository, required this.vaultId})
      : super(const GrantsListState());

  final GrantsRepository repository;
  final String vaultId;

  static const _pageSize = 20;

  /// Loads the first page with the current filters. Called on mount and
  /// after every filter change / pull-to-refresh.
  Future<void> load() async {
    emit(state.copyWith(
      status: GrantsListStatus.loading,
      clearError: true,
      grants: const [],
      clearNextCursor: true,
    ));
    try {
      final page = await repository.listGrants(
        vaultId,
        status: state.statusFilter,
        agentId: state.agentIdFilter,
        pageSize: _pageSize,
      );
      AppLogger.i('Grants', 'Loaded ${page.grants.length} grants');
      emit(state.copyWith(
        status: GrantsListStatus.loaded,
        grants: page.grants,
        nextCursor: page.nextCursor,
        clearNextCursor: page.nextCursor == null,
      ));
    } on GrantsException catch (e) {
      AppLogger.w('Grants', 'Grant load failed: ${e.kind.name}');
      emit(state.copyWith(status: GrantsListStatus.error, error: e.kind));
    } catch (e, s) {
      AppLogger.e('Grants', 'Grant load failed unexpectedly',
          error: e, stackTrace: s);
      emit(state.copyWith(
        status: GrantsListStatus.error,
        error: GrantsErrorKind.unknown,
      ));
    }
  }

  /// Fetches the next page and appends it. No-op when already loading or
  /// no further pages exist.
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    emit(state.copyWith(isLoadingMore: true));
    try {
      final page = await repository.listGrants(
        vaultId,
        status: state.statusFilter,
        agentId: state.agentIdFilter,
        cursor: state.nextCursor,
        pageSize: _pageSize,
      );
      emit(state.copyWith(
        grants: [...state.grants, ...page.grants],
        nextCursor: page.nextCursor,
        clearNextCursor: page.nextCursor == null,
        isLoadingMore: false,
      ));
    } on GrantsException catch (e) {
      AppLogger.w('Grants', 'Grant loadMore failed: ${e.kind.name}');
      emit(state.copyWith(isLoadingMore: false, mutationError: e.kind));
    } catch (e, s) {
      AppLogger.e('Grants', 'Grant loadMore failed unexpectedly',
          error: e, stackTrace: s);
      emit(state.copyWith(
        isLoadingMore: false,
        mutationError: GrantsErrorKind.unknown,
      ));
    }
  }

  /// Sets the status filter (wire string e.g. `"pending"`; `null` for
  /// all) and reloads the first page.
  Future<void> setStatusFilter(String? status) {
    emit(status == null
        ? state.copyWith(clearStatusFilter: true)
        : state.copyWith(statusFilter: status));
    return load();
  }

  /// Sets the agent filter (`null` for all) and reloads.
  Future<void> setAgentFilter(String? agentId) {
    emit(agentId == null
        ? state.copyWith(clearAgentIdFilter: true)
        : state.copyWith(agentIdFilter: agentId));
    return load();
  }

  /// Revokes a grant then reloads the list so its status reflects the
  /// change. The error is surfaced transiently so the list stays visible.
  Future<void> revokeGrant(String grantId, {String? reason}) async {
    emit(state.copyWith(
      revokingGrantId: grantId,
      clearMutationError: true,
    ));
    try {
      await repository.revokeGrant(vaultId, grantId, reason: reason);
      await load();
      emit(state.copyWith(clearRevokingGrantId: true));
    } on GrantsException catch (e) {
      AppLogger.w('Grants', 'revokeGrant failed: ${e.kind.name}');
      emit(state.copyWith(
        mutationError: e.kind,
        clearRevokingGrantId: true,
      ));
    } catch (e, s) {
      AppLogger.e('Grants', 'revokeGrant failed unexpectedly',
          error: e, stackTrace: s);
      emit(state.copyWith(
        mutationError: GrantsErrorKind.unknown,
        clearRevokingGrantId: true,
      ));
    }
  }

  /// Clears the transient mutation error after the UI shows its snackbar.
  void acknowledgeMutationError() {
    if (state.mutationError == null) return;
    emit(state.copyWith(clearMutationError: true));
  }
}
