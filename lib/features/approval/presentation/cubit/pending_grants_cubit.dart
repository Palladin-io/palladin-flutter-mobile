import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/pending_grant.dart';
import '../../domain/exceptions/approval_exceptions.dart';
import '../../domain/repositories/approval_repository.dart';

export '../../domain/entities/pending_grant.dart';

enum PendingGrantsStatus { initial, loading, loaded, error }

/// State for the cross-vault pending-grants list.
class PendingGrantsState {
  const PendingGrantsState({
    this.status = PendingGrantsStatus.initial,
    this.grants = const [],
    this.error,
  });

  final PendingGrantsStatus status;
  final List<PendingGrant> grants;
  final ApprovalErrorKind? error;

  PendingGrantsState copyWith({
    PendingGrantsStatus? status,
    List<PendingGrant>? grants,
    ApprovalErrorKind? error,
    bool clearError = false,
  }) {
    return PendingGrantsState(
      status: status ?? this.status,
      grants: grants ?? this.grants,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Loads the cross-vault list of pending grant requests for the approval
/// inbox. Factory-scoped per page mount (see DI).
class PendingGrantsCubit extends Cubit<PendingGrantsState> {
  PendingGrantsCubit({required this.repository})
    : super(const PendingGrantsState());

  final ApprovalRepository repository;

  Future<void> load() async {
    emit(state.copyWith(status: PendingGrantsStatus.loading, clearError: true));
    try {
      final grants = await repository.listPendingGrants();
      AppLogger.i('Approval', 'Loaded ${grants.length} pending grants');
      emit(state.copyWith(status: PendingGrantsStatus.loaded, grants: grants));
    } on ApprovalException catch (e) {
      AppLogger.w('Approval', 'pending load failed: ${e.kind.name}');
      emit(state.copyWith(status: PendingGrantsStatus.error, error: e.kind));
    } catch (e, s) {
      AppLogger.e(
        'Approval',
        'pending load failed unexpectedly',
        error: e,
        stackTrace: s,
      );
      emit(
        state.copyWith(
          status: PendingGrantsStatus.error,
          error: ApprovalErrorKind.unknown,
        ),
      );
    }
  }

  /// Quiet refetch that never flips to a loading/skeleton state and swallows
  /// errors — used to keep the nav badge live (from the shell, on SignalR
  /// pushes, on resume / tab taps) without disturbing an open inbox list.
  Future<void> refresh() async {
    try {
      final grants = await repository.listPendingGrants();
      emit(
        state.copyWith(
          status: PendingGrantsStatus.loaded,
          grants: grants,
          clearError: true,
        ),
      );
    } catch (e) {
      AppLogger.w('Approval', 'pending refresh failed (quiet): $e');
    }
  }

  /// Removes a grant from the in-memory list after it was approved/denied
  /// so the inbox reflects the change without a full reload.
  void removeGrant(String grantId) {
    emit(
      state.copyWith(
        grants: state.grants
            .where((g) => g.grantId != grantId)
            .toList(growable: false),
      ),
    );
  }
}
