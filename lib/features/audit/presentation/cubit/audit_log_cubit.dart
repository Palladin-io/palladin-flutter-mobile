import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../agents/domain/repositories/agents_repository.dart';
import '../../../vault/domain/repositories/vault_repository.dart';
import '../../domain/exceptions/audit_exceptions.dart';
import '../../domain/repositories/audit_repository.dart';
import 'audit_log_state.dart';

export 'audit_log_state.dart';

/// Drives the vault-scoped Logs tab (CVT-121) and the org-wide Logs screen
/// (CVT-66).
///
/// Pages the relevant audit feed (newest-first) and resolves agent / vault
/// names from their caches as a best-effort fallback — the backend now
/// denormalizes `agentName` / `actorName` server-side, so rows are correct
/// even before the caches resolve. All chip / dropdown / date / search
/// filtering is applied client-side over the loaded pages.
class AuditLogCubit extends Cubit<AuditLogState> {
  AuditLogCubit({
    required this.auditRepository,
    required this.agentsRepository,
    required this.vaultRepository,
    required AuditLogScope scope,
    this.vaultId,
  }) : super(AuditLogState(scope: scope));

  final AuditRepository auditRepository;
  final AgentsRepository agentsRepository;
  final VaultRepository vaultRepository;

  /// The vault to scope the feed to ([AuditLogScope.vault]); `null` for the
  /// org-wide feed.
  final String? vaultId;

  static const _pageSize = 50;

  Future<void> load() async {
    emit(state.copyWith(status: AuditLogStatus.loading, clearError: true));
    final names = await _resolveNames();
    try {
      final page = await _fetch();
      AppLogger.i('Audit', 'Loaded ${page.entries.length} audit logs');
      emit(
        state.copyWith(
          status: AuditLogStatus.loaded,
          entries: page.entries,
          agentNames: names.agents,
          vaultNames: names.vaults,
          nextCursor: page.nextCursor,
          clearNextCursor: page.nextCursor == null,
        ),
      );
    } on AuditException catch (e) {
      AppLogger.w('Audit', 'Audit log load failed: ${e.kind.name}');
      emit(state.copyWith(status: AuditLogStatus.error, error: e.kind));
    } catch (e, s) {
      AppLogger.e(
        'Audit',
        'Audit log load failed unexpectedly',
        error: e,
        stackTrace: s,
      );
      emit(
        state.copyWith(
          status: AuditLogStatus.error,
          error: AuditErrorKind.unknown,
        ),
      );
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || state.nextCursor == null) return;
    emit(state.copyWith(loadingMore: true, loadMoreError: false));
    try {
      final page = await _fetch(cursor: state.nextCursor);
      emit(
        state.copyWith(
          entries: [...state.entries, ...page.entries],
          nextCursor: page.nextCursor,
          clearNextCursor: page.nextCursor == null,
          loadingMore: false,
        ),
      );
    } catch (e, s) {
      AppLogger.e(
        'Audit',
        'Audit log loadMore failed',
        error: e,
        stackTrace: s,
      );
      emit(state.copyWith(loadingMore: false, loadMoreError: true));
    }
  }

  Future<void> reload() => load();

  /// Applies the filter sheet selection (event-type groups + agents + users +
  /// vaults + date range) in one emit. Every facet is multi-select; an empty
  /// set clears that facet.
  void applyFilter(AuditLogFilter filter) {
    emit(
      state.copyWith(
        groupFilters: filter.groups,
        agentFilters: filter.agentIds,
        userFilters: filter.userIds,
        vaultFilters: filter.vaultIds,
        fromDate: filter.fromDate,
        clearFromDate: filter.fromDate == null,
        toDate: filter.toDate,
        clearToDate: filter.toDate == null,
      ),
    );
  }

  void search(String query) => emit(state.copyWith(query: query));

  Future<AuditLogPage> _fetch({String? cursor}) {
    final vId = vaultId;
    if (state.scope == AuditLogScope.vault && vId != null) {
      return auditRepository.listVaultLogs(
        vId,
        cursor: cursor,
        pageSize: _pageSize,
      );
    }
    return auditRepository.listOrgLogs(cursor: cursor, pageSize: _pageSize);
  }

  Future<({Map<String, String> agents, Map<String, String> vaults})>
  _resolveNames() async {
    final agents = await _resolveAgentNames();
    final vaults = state.scope == AuditLogScope.org
        ? await _resolveVaultNames()
        : const <String, String>{};
    return (agents: agents, vaults: vaults);
  }

  Future<Map<String, String>> _resolveAgentNames() async {
    try {
      final agents = await agentsRepository.listAgents();
      return {
        for (final a in agents)
          if (a.name != null && a.name!.trim().isNotEmpty)
            a.agentId: a.name!.trim(),
      };
    } catch (e) {
      // Best-effort — a failure must not block the logs. Rows fall back to
      // the server-denormalized name or a shortened id.
      AppLogger.w('Audit', 'Agent name resolution failed: $e');
      return const {};
    }
  }

  Future<Map<String, String>> _resolveVaultNames() async {
    try {
      final vaults = await vaultRepository.listVaults();
      return {for (final v in vaults) v.id: v.name};
    } catch (e) {
      AppLogger.w('Audit', 'Vault name resolution failed: $e');
      return const {};
    }
  }
}
