import '../../domain/entities/grant.dart';
import '../../domain/exceptions/grants_exceptions.dart';

/// Load status of the grants list.
enum GrantsListStatus { initial, loading, loaded, error }

/// Immutable state for the grant-management list screen.
class GrantsListState {
  const GrantsListState({
    this.status = GrantsListStatus.initial,
    this.grants = const [],
    this.statusFilter,
    this.agentIdFilter,
    this.nextCursor,
    this.isLoadingMore = false,
    this.error,
    this.mutationError,
    this.revokingGrantId,
  });

  final GrantsListStatus status;

  /// Grants accumulated across loaded pages.
  final List<Grant> grants;

  /// Active status filter (wire string e.g. `"pending"`), or `null` for
  /// all statuses.
  final String? statusFilter;

  /// Active agent filter, or `null` for all agents.
  final String? agentIdFilter;

  /// Cursor for the next page, or `null` when fully loaded.
  final String? nextCursor;

  /// `true` while a "load more" page fetch is in flight.
  final bool isLoadingMore;

  /// Set when the initial list load failed — drives the full error state.
  final GrantsErrorKind? error;

  /// Transient error from a revoke mutation — shown as a snackbar, the
  /// list stays visible.
  final GrantsErrorKind? mutationError;

  /// Id of the grant currently being revoked, or `null` when none.
  final String? revokingGrantId;

  bool get hasMore => nextCursor != null;

  GrantsListState copyWith({
    GrantsListStatus? status,
    List<Grant>? grants,
    String? statusFilter,
    bool clearStatusFilter = false,
    String? agentIdFilter,
    bool clearAgentIdFilter = false,
    String? nextCursor,
    bool clearNextCursor = false,
    bool? isLoadingMore,
    GrantsErrorKind? error,
    bool clearError = false,
    GrantsErrorKind? mutationError,
    bool clearMutationError = false,
    String? revokingGrantId,
    bool clearRevokingGrantId = false,
  }) {
    return GrantsListState(
      status: status ?? this.status,
      grants: grants ?? this.grants,
      statusFilter:
          clearStatusFilter ? null : (statusFilter ?? this.statusFilter),
      agentIdFilter:
          clearAgentIdFilter ? null : (agentIdFilter ?? this.agentIdFilter),
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
      mutationError:
          clearMutationError ? null : (mutationError ?? this.mutationError),
      revokingGrantId: clearRevokingGrantId
          ? null
          : (revokingGrantId ?? this.revokingGrantId),
    );
  }
}
