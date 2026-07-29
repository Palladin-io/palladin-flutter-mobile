import '../../domain/entities/grant.dart';
import '../../domain/exceptions/grants_exceptions.dart';

enum OrgGrantsStatus { initial, loading, loaded, error }

/// State for the org-wide grants "history" feed shown on the Approvals
/// screen. Holds the full loaded list; filtering (status multi-select +
/// free-text search) is applied client-side via [filtered] so toggling a
/// filter never triggers a network round-trip.
class OrgGrantsState {
  const OrgGrantsState({
    this.status = OrgGrantsStatus.initial,
    this.grants = const [],
    this.error,
    this.statusFilter = const {},
    this.query = '',
    this.revokingGrantId,
    this.mutationError,
  });

  final OrgGrantsStatus status;

  /// Every loaded grant (already excludes pending — those live in the other
  /// segment). Newest-first as returned by the backend.
  final List<Grant> grants;

  final GrantsErrorKind? error;

  /// Selected statuses; empty = show all.
  final Set<GrantStatus> statusFilter;

  /// Free-text search over agent / entry / vault names.
  final String query;

  /// Grant currently being revoked (drives a per-card spinner), or `null`.
  final String? revokingGrantId;

  /// Transient revoke error surfaced as a snackbar, then acknowledged.
  final GrantsErrorKind? mutationError;

  /// The list after applying the status filter and search query.
  List<Grant> get filtered {
    final q = query.trim().toLowerCase();
    return grants
        .where((g) {
          if (statusFilter.isNotEmpty && !statusFilter.contains(g.status)) {
            return false;
          }
          if (q.isEmpty) return true;
          return [
            g.agentName,
            g.entryLabel,
            g.vaultName,
          ].whereType<String>().any((v) => v.toLowerCase().contains(q));
        })
        .toList(growable: false);
  }

  /// Per-status counts across the full (unfiltered) list — drives the summary
  /// line under the title.
  Map<GrantStatus, int> get counts {
    final map = <GrantStatus, int>{};
    for (final g in grants) {
      map[g.status] = (map[g.status] ?? 0) + 1;
    }
    return map;
  }

  OrgGrantsState copyWith({
    OrgGrantsStatus? status,
    List<Grant>? grants,
    GrantsErrorKind? error,
    bool clearError = false,
    Set<GrantStatus>? statusFilter,
    String? query,
    String? revokingGrantId,
    bool clearRevokingGrantId = false,
    GrantsErrorKind? mutationError,
    bool clearMutationError = false,
  }) {
    return OrgGrantsState(
      status: status ?? this.status,
      grants: grants ?? this.grants,
      error: clearError ? null : (error ?? this.error),
      statusFilter: statusFilter ?? this.statusFilter,
      query: query ?? this.query,
      revokingGrantId: clearRevokingGrantId
          ? null
          : (revokingGrantId ?? this.revokingGrantId),
      mutationError: clearMutationError
          ? null
          : (mutationError ?? this.mutationError),
    );
  }
}
