import '../../domain/entities/audit_log_entry.dart';
import '../../domain/exceptions/audit_exceptions.dart';

enum EntryLogsStatus { initial, loading, loaded, error }

/// An agent option for the Logs filter dropdown — id plus resolved name.
class AgentOption {
  const AgentOption({required this.id, required this.name});

  final String id;
  final String name;
}

/// State for the entry-detail Logs tab.
///
/// Holds every audit entry already scoped to the current entry (the
/// backend has no entry filter, so the cubit narrows the vault feed by
/// `entryId` before storing it here). The visible list is derived via
/// [filtered] — event-type multi-select, agent dropdown, date range and
/// free-text search are all applied client-side so toggling a filter
/// never triggers a network round-trip.
class EntryLogsState {
  const EntryLogsState({
    this.status = EntryLogsStatus.initial,
    this.entries = const [],
    this.agentNames = const {},
    this.error,
    this.nextCursor,
    this.loadingMore = false,
    this.loadMoreError = false,
    this.eventTypeFilter = const {},
    this.agentFilter,
    this.fromDate,
    this.toDate,
    this.query = '',
  });

  final EntryLogsStatus status;

  /// Every loaded entry already scoped to the current entry, newest-first.
  final List<AuditLogEntry> entries;

  /// Resolved agent id → display name, populated from the agents cache.
  final Map<String, String> agentNames;

  final AuditErrorKind? error;

  /// Cursor for the next vault page, or `null` when the vault feed is
  /// exhausted. Because entry scoping is client-side, more entry logs may
  /// live in later pages — drives the "Load more" affordance.
  final String? nextCursor;

  /// `true` while a "Load more" page request is in flight.
  final bool loadingMore;

  /// `true` when the last "Load more" page request failed — surfaces a
  /// one-shot inline error + retry next to the button. Cleared when a new
  /// "Load more" starts.
  final bool loadMoreError;

  /// Selected event types; empty = show all.
  final Set<AuditEventType> eventTypeFilter;

  /// Selected agent id, or `null` for all agents.
  final String? agentFilter;

  /// Inclusive lower / upper date bounds (local), or `null` for unbounded.
  final DateTime? fromDate;
  final DateTime? toDate;

  /// Free-text search over agent name, entry label, reason and event type.
  final String query;

  /// `true` when any client-side filter narrows the list.
  bool get hasActiveFilters =>
      eventTypeFilter.isNotEmpty ||
      agentFilter != null ||
      fromDate != null ||
      toDate != null;

  /// The distinct agents present across the loaded entries, for the agent
  /// dropdown. Sorted by display name.
  List<AgentOption> get agentOptions {
    final ids = <String>{};
    for (final e in entries) {
      if (e.agentId != null) ids.add(e.agentId!);
    }
    final options = ids
        .map((id) => AgentOption(id: id, name: agentNames[id] ?? _shortId(id)))
        .toList();
    options.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return options;
  }

  /// The entries after applying every client-side filter.
  List<AuditLogEntry> get filtered {
    final q = query.trim().toLowerCase();
    return entries.where((e) {
      if (eventTypeFilter.isNotEmpty &&
          !eventTypeFilter.contains(e.eventType)) {
        return false;
      }
      if (agentFilter != null && e.agentId != agentFilter) return false;
      if (fromDate != null && e.createdAt.isBefore(fromDate!)) return false;
      if (toDate != null && e.createdAt.isAfter(toDate!)) return false;
      if (q.isEmpty) return true;
      final agentName = e.agentId != null ? agentNames[e.agentId] : null;
      return [agentName, e.entryLabel, e.agentReason, e.rawEventType]
          .whereType<String>()
          .any((v) => v.toLowerCase().contains(q));
    }).toList(growable: false);
  }

  static String _shortId(String id) =>
      id.length <= 8 ? id : '${id.substring(0, 8)}…';

  EntryLogsState copyWith({
    EntryLogsStatus? status,
    List<AuditLogEntry>? entries,
    Map<String, String>? agentNames,
    AuditErrorKind? error,
    bool clearError = false,
    String? nextCursor,
    bool clearNextCursor = false,
    bool? loadingMore,
    bool? loadMoreError,
    Set<AuditEventType>? eventTypeFilter,
    String? agentFilter,
    bool clearAgentFilter = false,
    DateTime? fromDate,
    bool clearFromDate = false,
    DateTime? toDate,
    bool clearToDate = false,
    String? query,
  }) {
    return EntryLogsState(
      status: status ?? this.status,
      entries: entries ?? this.entries,
      agentNames: agentNames ?? this.agentNames,
      error: clearError ? null : (error ?? this.error),
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreError: loadMoreError ?? this.loadMoreError,
      eventTypeFilter: eventTypeFilter ?? this.eventTypeFilter,
      agentFilter: clearAgentFilter ? null : (agentFilter ?? this.agentFilter),
      fromDate: clearFromDate ? null : (fromDate ?? this.fromDate),
      toDate: clearToDate ? null : (toDate ?? this.toDate),
      query: query ?? this.query,
    );
  }
}
