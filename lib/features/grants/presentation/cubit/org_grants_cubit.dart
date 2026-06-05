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

  /// Loads the history feed (newest-first), dropping pending grants. Called on
  /// mount and on pull-to-refresh.
  Future<void> load() async {
    emit(state.copyWith(status: OrgGrantsStatus.loading, clearError: true));
    try {
      final page = await repository.listOrgGrants(pageSize: _pageSize);
      final grants = page.grants
          .where((g) => g.status != GrantStatus.pending)
          .toList(growable: false);
      AppLogger.i('Grants', 'Loaded ${grants.length} org grants');
      emit(state.copyWith(status: OrgGrantsStatus.loaded, grants: grants));
    } on GrantsException catch (e) {
      AppLogger.w('Grants', 'Org grant load failed: ${e.kind.name}');
      emit(state.copyWith(status: OrgGrantsStatus.error, error: e.kind));
    } catch (e, s) {
      AppLogger.e('Grants', 'Org grant load failed unexpectedly',
          error: e, stackTrace: s);
      emit(state.copyWith(
        status: OrgGrantsStatus.error,
        error: GrantsErrorKind.unknown,
      ));
    }
  }

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
  Future<void> revokeGrant(
    String vaultId,
    String grantId, {
    String? reason,
  }) async {
    emit(state.copyWith(revokingGrantId: grantId, clearMutationError: true));
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
