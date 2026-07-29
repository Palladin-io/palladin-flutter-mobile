import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../agents/domain/repositories/agents_repository.dart';
import '../../../vault/data/services/member_sync_service.dart';
import '../../../vault/presentation/cubit/vault_list_cubit.dart';
import '../../domain/entities/audit_log_entry.dart';
import '../../domain/exceptions/audit_exceptions.dart';
import '../../domain/repositories/audit_repository.dart';
import 'entry_logs_state.dart';

export 'entry_logs_state.dart';

/// Drives the entry-detail Logs tab.
///
/// Every request carries the opaque Vault + Entry scope. Presentation names
/// resolve only from unlocked local projections; legacy backend labels and
/// free-text metadata are discarded before state reaches the widget tree.
class EntryLogsCubit extends Cubit<EntryLogsState> {
  EntryLogsCubit({
    required this.auditRepository,
    required this.agentsRepository,
    required this.vaultListCubit,
    required this.memberSync,
    required this.vaultId,
    required this.entryId,
  }) : super(const EntryLogsState());

  final AuditRepository auditRepository;
  final AgentsRepository agentsRepository;
  final VaultListCubit vaultListCubit;
  final MemberIndexReader memberSync;
  final String vaultId;
  final String entryId;

  static const _pageSize = 50;
  static const _maximumLoadedEntries = 500;

  Future<void> load() async {
    emit(state.copyWith(status: EntryLogsStatus.loading, clearError: true));
    final names = await _resolveNames();
    try {
      final page = await _fetch();
      final entries = _resolvePage(page.entries, names);
      AppLogger.i('Audit', 'Loaded ${entries.length} entry audit logs');
      emit(
        state.copyWith(
          status: EntryLogsStatus.loaded,
          entries: entries,
          agentNames: names.agents,
          nextCursor: page.nextCursor,
          clearNextCursor: page.nextCursor == null,
        ),
      );
    } on AuditException catch (e) {
      AppLogger.w('Audit', 'Entry log load failed: ${e.kind.name}');
      emit(state.copyWith(status: EntryLogsStatus.error, error: e.kind));
    } catch (_) {
      AppLogger.e('Audit', 'Entry log load failed unexpectedly');
      emit(
        state.copyWith(
          status: EntryLogsStatus.error,
          error: AuditErrorKind.unknown,
        ),
      );
    }
  }

  /// Fetches the next vault page and appends any matching entry logs.
  Future<void> loadMore() async {
    if (state.loadingMore ||
        state.nextCursor == null ||
        state.entries.length >= _maximumLoadedEntries) {
      return;
    }
    emit(state.copyWith(loadingMore: true, loadMoreError: false));
    try {
      final cursor = state.nextCursor!;
      final page = await _fetch(cursor: cursor);
      if (page.nextCursor == cursor) {
        throw const FormatException('Repeated Audit cursor');
      }
      final hasUnknownAgent = page.entries.any(
        (entry) =>
            entry.agentId != null &&
            !state.agentNames.containsKey(entry.agentId),
      );
      final agentNames = hasUnknownAgent
          ? {...state.agentNames, ...await _resolveAgentNames()}
          : state.agentNames;
      final remaining = _maximumLoadedEntries - state.entries.length;
      final more = _resolvePage(page.entries, (
        agents: agentNames,
        vault: state.entries.isEmpty
            ? null
            : state.entries.first.resolvedVaultName,
        entry: state.entries.isEmpty ? null : state.entries.first.entryLabel,
      )).take(remaining).toList(growable: false);
      final reachedLimit = more.length >= remaining;

      emit(
        state.copyWith(
          entries: [...state.entries, ...more],
          agentNames: agentNames,
          nextCursor: reachedLimit ? null : page.nextCursor,
          clearNextCursor: reachedLimit || page.nextCursor == null,
          loadingMore: false,
        ),
      );
    } catch (_) {
      AppLogger.e('Audit', 'Entry log loadMore failed');
      emit(state.copyWith(loadingMore: false, loadMoreError: true));
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
    emit(
      state.copyWith(
        eventTypeFilter: eventTypes,
        agentFilter: agentId,
        clearAgentFilter: agentId == null,
        fromDate: from,
        clearFromDate: from == null,
        toDate: to,
        clearToDate: to == null,
      ),
    );
  }

  void search(String query) => emit(state.copyWith(query: query));

  Future<AuditLogPage> _fetch({String? cursor}) =>
      auditRepository.listVaultLogs(
        vaultId,
        entryId: entryId,
        cursor: cursor,
        pageSize: _pageSize,
      );

  Future<({Map<String, String> agents, String? vault, String? entry})>
  _resolveNames() async {
    final agents = await _resolveAgentNames();
    String? vaultName;
    try {
      final state = vaultListCubit.state;
      if (state is VaultListLoaded) {
        for (final vault in state.vaults) {
          if (vault.id == vaultId) {
            vaultName = vault.name;
            break;
          }
        }
      }
    } catch (_) {
      AppLogger.w('Audit', 'Vault name resolution failed');
    }
    try {
      await memberSync.waitForCurrent(vaultId);
    } catch (_) {
      AppLogger.w('Audit', 'Member index wait failed');
    }
    String? entryName;
    for (final candidate in memberSync.entries(vaultId)) {
      if (candidate.entryId == entryId && !candidate.corrupt) {
        entryName = candidate.memberLabel;
        break;
      }
    }
    return (agents: agents, vault: vaultName, entry: entryName);
  }

  List<AuditLogEntry> _resolvePage(
    List<AuditLogEntry> page,
    ({Map<String, String> agents, String? vault, String? entry}) names,
  ) => page
      .map((item) {
        if (item.vaultId != vaultId || item.entryId != entryId) {
          throw const FormatException('Audit Entry scope mismatch');
        }
        final agentName = item.agentId == null
            ? null
            : names.agents[item.agentId];
        return AuditLogEntry(
          id: item.id,
          eventType: item.eventType,
          rawEventType: item.rawEventType,
          actorType: item.actorType,
          result: item.result,
          occurredAt: item.occurredAt,
          createdAt: item.createdAt,
          userId: item.userId,
          agentId: item.agentId,
          agentName: agentName ?? item.agentName,
          actorName: item.actorName,
          vaultId: item.vaultId,
          entryId: item.entryId,
          entryLabel: names.entry ?? _shortId(item.entryId!),
          resolvedObjectName: names.entry ?? _shortId(item.entryId!),
          resolvedVaultName: names.vault ?? _shortId(item.vaultId!),
          localPresentationOnly: true,
          metadata: item.metadata,
        );
      })
      .toList(growable: false);

  String _shortId(String value) => value.length <= 15
      ? value
      : '${value.substring(0, 8)}…${value.substring(value.length - 6)}';

  Future<Map<String, String>> _resolveAgentNames() async {
    try {
      final agents = await agentsRepository.listAgents();
      return {
        for (final a in agents)
          if (a.name != null && a.name!.trim().isNotEmpty)
            a.agentId: a.name!.trim(),
      };
    } catch (_) {
      // Agent name resolution is best-effort — a failure here must not
      // block the logs. Rows fall back to a shortened agent id.
      AppLogger.w('Audit', 'Agent name resolution failed');
      return const {};
    }
  }
}
