import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../agents/domain/repositories/agents_repository.dart';
import '../../domain/entities/audit_log_entry.dart';
import '../../domain/exceptions/audit_exceptions.dart';
import '../../domain/repositories/audit_repository.dart';
import 'entry_logs_state.dart';

export 'entry_logs_state.dart';

/// Drives the entry-detail Logs tab.
///
/// The backend audit endpoints are vault-scoped with no entry filter and
/// return agent **ids** (not names), so this cubit:
///   1. resolves agent id → name from the agents cache, and
///   2. pages the vault audit feed (newest-first) and keeps only the
///      entries whose `entryId` matches the current entry.
///
/// On the first load it auto-fetches a few pages until it finds entry-
/// scoped logs (or the feed is exhausted) so a quiet first page doesn't
/// render a false "empty". Further history is reachable via [loadMore].
/// All filtering (event type, agent, date range, search) is client-side.
class EntryLogsCubit extends Cubit<EntryLogsState> {
  EntryLogsCubit({
    required this.auditRepository,
    required this.agentsRepository,
    required this.vaultId,
    required this.entryId,
  }) : super(const EntryLogsState());

  final AuditRepository auditRepository;
  final AgentsRepository agentsRepository;
  final String vaultId;
  final String entryId;

  static const _pageSize = 50;

  /// Pages auto-fetched on the first load while no entry-scoped entry has
  /// been found yet — bounds the network cost for entries with no logs.
  static const _maxInitialPages = 5;

  Future<void> load() async {
    emit(state.copyWith(status: EntryLogsStatus.loading, clearError: true));
    final agentNames = await _resolveAgentNames();
    try {
      final collected = <AuditLogEntry>[];
      String? cursor;
      var pages = 0;
      var exhausted = false;
      do {
        final page = await auditRepository.listVaultLogs(
          vaultId,
          cursor: cursor,
          pageSize: _pageSize,
        );
        collected.addAll(page.entries.where((e) => e.entryId == entryId));
        cursor = page.nextCursor;
        exhausted = cursor == null;
        pages++;
      } while (!exhausted && collected.isEmpty && pages < _maxInitialPages);

      AppLogger.i('Audit', 'Loaded ${collected.length} entry audit logs');
      emit(state.copyWith(
        status: EntryLogsStatus.loaded,
        entries: collected,
        agentNames: agentNames,
        nextCursor: cursor,
        clearNextCursor: exhausted,
      ));
    } on AuditException catch (e) {
      AppLogger.w('Audit', 'Entry log load failed: ${e.kind.name}');
      emit(state.copyWith(status: EntryLogsStatus.error, error: e.kind));
    } catch (e, s) {
      AppLogger.e('Audit', 'Entry log load failed unexpectedly',
          error: e, stackTrace: s);
      emit(state.copyWith(
        status: EntryLogsStatus.error,
        error: AuditErrorKind.unknown,
      ));
    }
  }

  /// Fetches the next vault page and appends any matching entry logs.
  Future<void> loadMore() async {
    if (state.loadingMore || state.nextCursor == null) return;
    emit(state.copyWith(loadingMore: true));
    try {
      final page = await auditRepository.listVaultLogs(
        vaultId,
        cursor: state.nextCursor,
        pageSize: _pageSize,
      );
      final more = page.entries.where((e) => e.entryId == entryId);
      emit(state.copyWith(
        entries: [...state.entries, ...more],
        nextCursor: page.nextCursor,
        clearNextCursor: page.nextCursor == null,
        loadingMore: false,
      ));
    } catch (e, s) {
      AppLogger.e('Audit', 'Entry log loadMore failed',
          error: e, stackTrace: s);
      emit(state.copyWith(loadingMore: false));
    }
  }

  Future<void> reload() => load();

  /// Applies the full filter selection from the filter sheet in one emit
  /// (event types + agent + date range). Passing an empty/null selection
  /// clears the corresponding filter. No refetch — filtering is local.
  void applyFilters({
    required Set<AuditEventType> eventTypes,
    String? agentId,
    DateTime? from,
    DateTime? to,
  }) {
    emit(state.copyWith(
      eventTypeFilter: eventTypes,
      agentFilter: agentId,
      clearAgentFilter: agentId == null,
      fromDate: from,
      clearFromDate: from == null,
      toDate: to,
      clearToDate: to == null,
    ));
  }

  void search(String query) => emit(state.copyWith(query: query));

  Future<Map<String, String>> _resolveAgentNames() async {
    try {
      final agents = await agentsRepository.listAgents();
      return {
        for (final a in agents)
          if (a.name != null && a.name!.trim().isNotEmpty)
            a.agentId: a.name!.trim(),
      };
    } catch (e) {
      // Agent name resolution is best-effort — a failure here must not
      // block the logs. Rows fall back to a shortened agent id.
      AppLogger.w('Audit', 'Agent name resolution failed: $e');
      return const {};
    }
  }
}
