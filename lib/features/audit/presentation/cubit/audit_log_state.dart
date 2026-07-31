import '../../domain/entities/audit_log_entry.dart';
import '../../domain/exceptions/audit_exceptions.dart';
import '../audit_filters.dart';

export '../audit_filters.dart'
    show AgentOption, VaultOption, UserOption, AuditLogFilter;

enum AuditLogStatus { initial, loading, loaded, error }

/// Whether the feed is scoped to a single vault (CVT-121, the vault-detail
/// Logs tab) or org-wide (CVT-66, the global Logs screen).
enum AuditLogScope { vault, org }

/// State for the shared vault-/org-scoped audit Logs surfaces.
///
/// Holds every loaded audit entry (newest-first). The visible list is derived
/// via [filtered] — event-type [groupFilters], an agent dropdown, an optional
/// vault dropdown (org scope), a date range and free-text search are all
/// applied client-side (from the one filter sheet) so toggling a filter never
/// triggers a network round-trip.
class AuditLogState {
  const AuditLogState({
    required this.scope,
    this.status = AuditLogStatus.initial,
    this.entries = const [],
    this.agentNames = const {},
    this.vaultNames = const {},
    this.entryNames = const {},
    this.memberNames = const {},
    this.error,
    this.nextCursor,
    this.loadingMore = false,
    this.loadMoreError = false,
    this.groupFilters = const {},
    this.agentFilters = const {},
    this.userFilters = const {},
    this.vaultFilters = const {},
    this.fromDate,
    this.toDate,
    this.query = '',
  });

  final AuditLogScope scope;
  final AuditLogStatus status;

  /// Every loaded entry, newest-first as returned by the backend.
  final List<AuditLogEntry> entries;

  /// Resolved agent id → display name (fallback when the server omits names).
  final Map<String, String> agentNames;

  /// Resolved vault id → name (org scope) for the dropdown and search.
  final Map<String, String> vaultNames;
  final Map<String, String> entryNames;
  final Map<String, String> memberNames;

  final AuditErrorKind? error;

  /// Cursor for the next page, or `null` when the feed is exhausted.
  final String? nextCursor;
  final bool loadingMore;
  final bool loadMoreError;

  /// Selected event-type groups; empty = all event types.
  final Set<AuditEventGroup> groupFilters;

  /// Selected agent / user (actor) / vault ids; empty = all. Multi-select:
  /// values within a facet are OR-ed, facets are AND-ed.
  final Set<String> agentFilters;
  final Set<String> userFilters;
  final Set<String> vaultFilters;

  /// Inclusive lower / upper date bounds (local), or `null` for unbounded.
  final DateTime? fromDate;
  final DateTime? toDate;

  /// Free-text search over actor/agent/entry/vault names, reason and type.
  final String query;

  /// `true` when any client-side filter from the sheet narrows the list.
  bool get hasActiveFilters =>
      groupFilters.isNotEmpty ||
      agentFilters.isNotEmpty ||
      userFilters.isNotEmpty ||
      vaultFilters.isNotEmpty ||
      fromDate != null ||
      toDate != null;

  /// The current selection, for seeding the filter sheet.
  AuditLogFilter get filter => AuditLogFilter(
    groups: groupFilters,
    agentIds: agentFilters,
    userIds: userFilters,
    vaultIds: vaultFilters,
    fromDate: fromDate,
    toDate: toDate,
  );

  /// The distinct agents present across the loaded entries, sorted by name.
  List<AgentOption> get agentOptions {
    final ids = <String>{};
    final names = <String, String>{};
    for (final e in entries) {
      final id = e.agentId;
      if (id == null) continue;
      ids.add(id);
      final name = e.agentName?.trim() ?? agentNames[id];
      if (name != null && name.isNotEmpty) names[id] = name;
    }
    final options = ids
        .map((id) => AgentOption(id: id, name: names[id] ?? _shortId(id)))
        .toList();
    options.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return options;
  }

  /// The distinct vaults present across the loaded entries, sorted by name.
  List<VaultOption> get vaultOptions {
    final ids = <String>{};
    for (final e in entries) {
      if (e.vaultId != null) ids.add(e.vaultId!);
    }
    final options = ids
        .map((id) => VaultOption(id: id, name: vaultNames[id] ?? _shortId(id)))
        .toList();
    options.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return options;
  }

  /// The distinct human actors (user-type) present across the loaded entries,
  /// sorted by display name. Falls back to distinct actors from the results
  /// when no org member directory is available; the name comes from the
  /// server-denormalized `actorName`. When no name is known the option's
  /// [UserOption.name] is left `null` so the presentation layer renders a
  /// localized "Unknown user ({shortId})" label — each unknown actor is a
  /// distinct, filterable option, never a bare id.
  List<UserOption> get userOptions {
    final names = <String, String?>{};
    for (final e in entries) {
      if (e.actorType != AuditActorType.user) continue;
      final id = e.userId;
      if (id == null) continue;
      final name = memberNames[id]?.trim() ?? e.actorName?.trim();
      if (name != null && name.isNotEmpty) {
        // A resolved name always wins over a previously-seen unknown.
        names[id] = name;
      } else {
        names.putIfAbsent(id, () => null);
      }
    }
    final options = names.entries
        .map((e) => UserOption(id: e.key, name: e.value))
        .toList();
    options.sort(
      (a, b) =>
          (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase()),
    );
    return options;
  }

  /// The entries after applying every client-side filter.
  List<AuditLogEntry> get filtered {
    final q = query.trim().toLowerCase();
    return entries
        .where((e) {
          if (groupFilters.isNotEmpty &&
              !groupFilters.contains(e.eventType.group)) {
            return false;
          }
          if (agentFilters.isNotEmpty &&
              (e.agentId == null || !agentFilters.contains(e.agentId))) {
            return false;
          }
          if (userFilters.isNotEmpty &&
              (e.userId == null || !userFilters.contains(e.userId))) {
            return false;
          }
          if (vaultFilters.isNotEmpty &&
              (e.vaultId == null || !vaultFilters.contains(e.vaultId))) {
            return false;
          }
          if (fromDate != null && e.occurredAt.isBefore(fromDate!)) {
            return false;
          }
          if (toDate != null && e.occurredAt.isAfter(toDate!)) {
            return false;
          }
          if (q.isEmpty) return true;
          final agentName =
              e.agentName ?? (e.agentId != null ? agentNames[e.agentId] : null);
          final vaultName = e.vaultId != null ? vaultNames[e.vaultId] : null;
          return [
            e.actorName,
            agentName,
            e.entryLabel,
            vaultName,
            e.agentId,
            e.userId,
            e.entryId,
            e.vaultId,
            e.rawEventType,
          ].whereType<String>().any((v) => v.toLowerCase().contains(q));
        })
        .toList(growable: false);
  }

  static String _shortId(String id) => id.length <= 15
      ? id
      : '${id.substring(0, 8)}…${id.substring(id.length - 6)}';

  AuditLogState copyWith({
    AuditLogStatus? status,
    List<AuditLogEntry>? entries,
    Map<String, String>? agentNames,
    Map<String, String>? vaultNames,
    Map<String, String>? entryNames,
    Map<String, String>? memberNames,
    AuditErrorKind? error,
    bool clearError = false,
    String? nextCursor,
    bool clearNextCursor = false,
    bool? loadingMore,
    bool? loadMoreError,
    Set<AuditEventGroup>? groupFilters,
    Set<String>? agentFilters,
    Set<String>? userFilters,
    Set<String>? vaultFilters,
    DateTime? fromDate,
    bool clearFromDate = false,
    DateTime? toDate,
    bool clearToDate = false,
    String? query,
  }) {
    return AuditLogState(
      scope: scope,
      status: status ?? this.status,
      entries: entries ?? this.entries,
      agentNames: agentNames ?? this.agentNames,
      vaultNames: vaultNames ?? this.vaultNames,
      entryNames: entryNames ?? this.entryNames,
      memberNames: memberNames ?? this.memberNames,
      error: clearError ? null : (error ?? this.error),
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreError: loadMoreError ?? this.loadMoreError,
      groupFilters: groupFilters ?? this.groupFilters,
      agentFilters: agentFilters ?? this.agentFilters,
      userFilters: userFilters ?? this.userFilters,
      vaultFilters: vaultFilters ?? this.vaultFilters,
      fromDate: clearFromDate ? null : (fromDate ?? this.fromDate),
      toDate: clearToDate ? null : (toDate ?? this.toDate),
      query: query ?? this.query,
    );
  }
}
