import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../agents/domain/repositories/agents_repository.dart';
import '../../../vault/domain/repositories/vault_repository.dart';
import '../../../vault/data/services/member_sync_service.dart';
import '../../domain/entities/audit_log_entry.dart';
import '../../domain/exceptions/audit_exceptions.dart';
import '../../domain/repositories/audit_repository.dart';
import 'audit_log_state.dart';

export 'audit_log_state.dart';

/// Drives the vault-scoped Logs tab (CVT-121) and the org-wide Logs screen
/// (CVT-66).
///
/// Pages the relevant audit feed (newest-first) and resolves agent / vault
/// names from unlocked local projections for Vault-scoped logs. All chip /
/// dropdown / date / search filtering is applied client-side over loaded
/// pages with a fixed in-memory ceiling.
class AuditLogCubit extends Cubit<AuditLogState> {
  AuditLogCubit({
    required this.auditRepository,
    required this.agentsRepository,
    required this.vaultRepository,
    required this.memberSync,
    required AuditLogScope scope,
    this.vaultId,
  }) : super(AuditLogState(scope: scope));

  final AuditRepository auditRepository;
  final AgentsRepository agentsRepository;
  final VaultRepository vaultRepository;
  final MemberIndexReader memberSync;

  /// The vault to scope the feed to ([AuditLogScope.vault]); `null` for the
  /// org-wide feed.
  final String? vaultId;

  static const _pageSize = 50;
  static const _maximumLoadedEntries = 2000;

  Future<void> load() async {
    emit(state.copyWith(status: AuditLogStatus.loading, clearError: true));
    final names = await _resolveNames();
    try {
      final page = await _fetch();
      AppLogger.i('Audit', 'Loaded ${page.entries.length} audit logs');
      emit(
        state.copyWith(
          status: AuditLogStatus.loaded,
          entries: _resolvePage(page.entries, names),
          agentNames: names.agents,
          vaultNames: names.vaults,
          entryNames: names.entries,
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
    if (state.loadingMore ||
        state.nextCursor == null ||
        state.entries.length >= _maximumLoadedEntries) {
      return;
    }
    emit(state.copyWith(loadingMore: true, loadMoreError: false));
    try {
      final page = await _fetch(cursor: state.nextCursor);
      final remaining = _maximumLoadedEntries - state.entries.length;
      final appended = _resolvePage(
        page.entries,
        _namesFromState(),
      ).take(remaining).toList(growable: false);
      final reachedLimit = appended.length >= remaining;
      emit(
        state.copyWith(
          entries: [...state.entries, ...appended],
          nextCursor: reachedLimit ? null : page.nextCursor,
          clearNextCursor: reachedLimit || page.nextCursor == null,
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

  Future<
    ({
      Map<String, String> agents,
      Map<String, String> vaults,
      Map<String, String> entries,
    })
  >
  _resolveNames() async {
    final agents = await _resolveAgentNames();
    final vaults = await _resolveVaultNames();
    final vId = vaultId;
    if (vId != null) {
      try {
        await memberSync.waitForCurrent(vId);
      } catch (e) {
        AppLogger.w('Audit', 'Member index wait failed: $e');
      }
    }
    final entries = vId == null
        ? const <String, String>{}
        : {
            for (final entry in memberSync.entries(vId))
              if (!entry.corrupt) entry.entryId: entry.memberLabel,
          };
    return (agents: agents, vaults: vaults, entries: entries);
  }

  ({
    Map<String, String> agents,
    Map<String, String> vaults,
    Map<String, String> entries,
  })
  _namesFromState() => (
    agents: state.agentNames,
    vaults: state.vaultNames,
    entries: state.entryNames,
  );

  List<AuditLogEntry> _resolvePage(
    List<AuditLogEntry> page,
    ({
      Map<String, String> agents,
      Map<String, String> vaults,
      Map<String, String> entries,
    })
    names,
  ) => page
      .map((entry) {
        final entryName = entry.entryId == null
            ? null
            : names.entries[entry.entryId];
        final vaultName = entry.vaultId == null
            ? null
            : names.vaults[entry.vaultId];
        final agentName = entry.agentId == null
            ? null
            : names.agents[entry.agentId];
        if (state.scope == AuditLogScope.org) {
          return AuditLogEntry(
            id: entry.id,
            eventType: entry.eventType,
            rawEventType: entry.rawEventType,
            actorType: entry.actorType,
            createdAt: entry.createdAt,
            userId: entry.userId,
            agentId: entry.agentId,
            agentName: entry.agentName ?? agentName,
            actorName: entry.actorName,
            vaultId: entry.vaultId,
            entryId: entry.entryId,
            entryLabel: entry.entryLabel,
            agentReason: entry.agentReason,
            resolvedObjectName: vaultName,
            metadata: entry.metadata,
          );
        }
        return AuditLogEntry(
          id: entry.id,
          eventType: entry.eventType,
          rawEventType: entry.rawEventType,
          actorType: entry.actorType,
          createdAt: entry.createdAt,
          userId: entry.userId,
          agentId: entry.agentId,
          agentName: agentName,
          vaultId: entry.vaultId,
          entryId: entry.entryId,
          entryLabel: entryName,
          resolvedObjectName: entryName ?? vaultName,
          localPresentationOnly: true,
          metadata: entry.metadata,
        );
      })
      .toList(growable: false);

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
