import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../agents/domain/repositories/agents_repository.dart';
import '../../../vault/domain/repositories/vault_members_repository.dart';
import '../../../vault/domain/entities/vault_entity.dart';
import '../../../vault/data/services/member_sync_service.dart';
import '../../../vault/presentation/cubit/vault_list_cubit.dart';
import '../../domain/entities/audit_log_entry.dart';
import '../../domain/exceptions/audit_exceptions.dart';
import '../../domain/repositories/audit_repository.dart';
import 'audit_log_state.dart';

export 'audit_log_state.dart';

typedef _AuditNames = ({
  Map<String, String> agents,
  Map<String, String> vaults,
  Map<String, String> entries,
  Map<String, String> members,
});

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
    required this.vaultListCubit,
    required this.vaultMembersRepository,
    required this.memberSync,
    required AuditLogScope scope,
    this.vaultId,
    this.maximumLoadedEntries = 2000,
    this.entryNameRefreshDelay = const Duration(milliseconds: 250),
  }) : super(AuditLogState(scope: scope));

  final AuditRepository auditRepository;
  final AgentsRepository agentsRepository;
  final VaultListCubit vaultListCubit;
  final VaultMembersRepository vaultMembersRepository;
  final MemberIndexReader memberSync;
  final int maximumLoadedEntries;

  /// One bounded post-load pass closes the race where the Logs tab mounts
  /// immediately before Vault MemberIndex synchronization is registered.
  /// The pass reads only the unlocked in-memory index.
  final Duration entryNameRefreshDelay;

  /// The vault to scope the feed to ([AuditLogScope.vault]); `null` for the
  /// org-wide feed.
  final String? vaultId;

  static const _pageSize = 50;
  final Set<String> _seenCursors = {};
  int _loadGeneration = 0;

  Future<void> load() async {
    final generation = ++_loadGeneration;
    emit(state.copyWith(status: AuditLogStatus.loading, clearError: true));
    _seenCursors.clear();
    try {
      final page = await _fetch();
      final names = await _resolveNames(page.entries);
      final accepted = page.entries
          .take(maximumLoadedEntries)
          .toList(growable: false);
      final scopedNames = _retainNamesForEntries(names, accepted);
      final reachedLimit = accepted.length >= maximumLoadedEntries;
      AppLogger.i('Audit', 'Loaded ${page.entries.length} audit logs');
      emit(
        state.copyWith(
          status: AuditLogStatus.loaded,
          entries: _resolvePage(accepted, scopedNames),
          agentNames: scopedNames.agents,
          vaultNames: scopedNames.vaults,
          entryNames: scopedNames.entries,
          memberNames: scopedNames.members,
          nextCursor: reachedLimit ? null : page.nextCursor,
          clearNextCursor: reachedLimit || page.nextCursor == null,
        ),
      );
      await _refreshEntryNamesAfterSync(generation);
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

  Future<void> _refreshEntryNamesAfterSync(int generation) async {
    if (entryNameRefreshDelay == Duration.zero || isClosed) return;
    final unresolved = state.entries.any(
      (entry) => entry.entryId != null && entry.entryLabel == null,
    );
    if (!unresolved) return;

    await Future<void>.delayed(entryNameRefreshDelay);
    if (isClosed || generation != _loadGeneration) return;

    final refreshed = await _resolveNames(state.entries);
    if (isClosed || generation != _loadGeneration) return;
    final merged = _mergeNames(_namesFromState(), refreshed);
    final retained = _retainNamesForEntries(merged, state.entries);
    final resolvedEntries = _resolvePage(state.entries, retained);
    final gainedName = resolvedEntries.indexed.any(
      (item) =>
          state.entries[item.$1].entryLabel == null &&
          item.$2.entryLabel != null,
    );
    if (!gainedName) return;

    emit(
      state.copyWith(
        entries: resolvedEntries,
        agentNames: retained.agents,
        vaultNames: retained.vaults,
        entryNames: retained.entries,
        memberNames: retained.members,
      ),
    );
  }

  Future<void> loadMore() async {
    if (state.loadingMore ||
        state.nextCursor == null ||
        state.entries.length >= maximumLoadedEntries) {
      return;
    }
    emit(state.copyWith(loadingMore: true, loadMoreError: false));
    try {
      final requestedCursor = state.nextCursor!;
      if (!_seenCursors.add(requestedCursor)) {
        emit(state.copyWith(loadingMore: false, clearNextCursor: true));
        return;
      }
      final page = await _fetch(cursor: requestedCursor);
      final names = await _resolveNames(page.entries);
      final mergedNames = _mergeNames(_namesFromState(), names);
      final remaining = maximumLoadedEntries - state.entries.length;
      final existingIds = state.entries.map((entry) => entry.id).toSet();
      final appended = _resolvePage(
        page.entries.where((entry) => existingIds.add(entry.id)).toList(),
        mergedNames,
      ).take(remaining).toList(growable: false);
      final reachedLimit = appended.length >= remaining;
      final repeatedCursor =
          page.nextCursor == requestedCursor ||
          (page.nextCursor != null && _seenCursors.contains(page.nextCursor));
      final allEntries = [...state.entries, ...appended];
      final retainedNames = _retainNamesForEntries(mergedNames, allEntries);
      emit(
        state.copyWith(
          entries: allEntries,
          agentNames: retainedNames.agents,
          vaultNames: retainedNames.vaults,
          entryNames: retainedNames.entries,
          memberNames: retainedNames.members,
          nextCursor: reachedLimit || repeatedCursor ? null : page.nextCursor,
          clearNextCursor:
              reachedLimit || repeatedCursor || page.nextCursor == null,
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
      Map<String, String> members,
    })
  >
  _resolveNames(List<AuditLogEntry> page) async {
    final agents = await _resolveAgentNames();
    final vaults = await _resolveVaultNames();
    final requestedAgentIds = page
        .map((entry) => entry.agentId)
        .whereType<String>()
        .toSet();
    final scopedAgents = Map.fromEntries(
      agents.entries.where((entry) => requestedAgentIds.contains(entry.key)),
    );
    final requestedVaultIds = page
        .map((entry) => entry.vaultId)
        .whereType<String>()
        .toSet();
    final allowedVaultIds =
        state.scope == AuditLogScope.vault && vaultId != null
        ? {vaultId!}
        : requestedVaultIds.intersection(vaults.keys.toSet());
    final scopedVaults = Map.fromEntries(
      vaults.entries.where((entry) => allowedVaultIds.contains(entry.key)),
    );
    final entries = <String, String>{};
    final members = <String, String>{};
    for (final vId in allowedVaultIds) {
      try {
        await memberSync.waitForCurrent(vId);
        final requestedEntryIds = page
            .where((entry) => entry.vaultId == vId)
            .map((entry) => entry.entryId)
            .whereType<String>()
            .toSet();
        for (final entry in memberSync.entries(vId)) {
          if (!entry.corrupt && requestedEntryIds.contains(entry.entryId)) {
            entries[entry.entryId] = entry.memberLabel;
          }
        }
      } catch (_) {
        AppLogger.w('Audit', 'Local entry-name resolution failed');
      }
      try {
        final requestedMemberIds = page
            .where((entry) => entry.vaultId == vId)
            .map((entry) => entry.userId)
            .whereType<String>()
            .toSet();
        final directory = await vaultMembersRepository.list(vId);
        for (final member in directory) {
          final name = member.name?.trim();
          if (requestedMemberIds.contains(member.id) &&
              name != null &&
              name.isNotEmpty) {
            members[member.id] = name;
          }
        }
      } catch (_) {
        AppLogger.w('Audit', 'Local member-name resolution failed');
      }
    }
    return (
      agents: scopedAgents,
      vaults: scopedVaults,
      entries: entries,
      members: members,
    );
  }

  ({
    Map<String, String> agents,
    Map<String, String> vaults,
    Map<String, String> entries,
    Map<String, String> members,
  })
  _namesFromState() => (
    agents: state.agentNames,
    vaults: state.vaultNames,
    entries: state.entryNames,
    members: state.memberNames,
  );

  ({
    Map<String, String> agents,
    Map<String, String> vaults,
    Map<String, String> entries,
    Map<String, String> members,
  })
  _mergeNames(
    ({
      Map<String, String> agents,
      Map<String, String> vaults,
      Map<String, String> entries,
      Map<String, String> members,
    })
    current,
    ({
      Map<String, String> agents,
      Map<String, String> vaults,
      Map<String, String> entries,
      Map<String, String> members,
    })
    page,
  ) => (
    agents: {...current.agents, ...page.agents},
    vaults: {...current.vaults, ...page.vaults},
    entries: {...current.entries, ...page.entries},
    members: {...current.members, ...page.members},
  );

  _AuditNames _retainNamesForEntries(
    _AuditNames names,
    List<AuditLogEntry> entries,
  ) {
    final agentIds = entries
        .map((entry) => entry.agentId)
        .whereType<String>()
        .toSet();
    final vaultIds = entries
        .map((entry) => entry.vaultId)
        .whereType<String>()
        .toSet();
    final entryIds = entries
        .map((entry) => entry.entryId)
        .whereType<String>()
        .toSet();
    final memberIds = entries
        .map((entry) => entry.userId)
        .whereType<String>()
        .toSet();
    return (
      agents: Map.fromEntries(
        names.agents.entries.where((entry) => agentIds.contains(entry.key)),
      ),
      vaults: Map.fromEntries(
        names.vaults.entries.where((entry) => vaultIds.contains(entry.key)),
      ),
      entries: Map.fromEntries(
        names.entries.entries.where((entry) => entryIds.contains(entry.key)),
      ),
      members: Map.fromEntries(
        names.members.entries.where((entry) => memberIds.contains(entry.key)),
      ),
    );
  }

  List<AuditLogEntry> _resolvePage(
    List<AuditLogEntry> page,
    ({
      Map<String, String> agents,
      Map<String, String> vaults,
      Map<String, String> entries,
      Map<String, String> members,
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
        final memberName = entry.userId == null
            ? null
            : names.members[entry.userId];
        return AuditLogEntry(
          id: entry.id,
          eventType: entry.eventType,
          rawEventType: entry.rawEventType,
          actorType: entry.actorType,
          result: entry.result,
          occurredAt: entry.occurredAt,
          createdAt: entry.createdAt,
          userId: entry.userId,
          agentId: entry.agentId,
          agentName: agentName,
          actorName: memberName,
          vaultId: entry.vaultId,
          entryId: entry.entryId,
          entryLabel: entryName,
          resolvedObjectName: entryName ?? vaultName,
          resolvedVaultName: vaultName,
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
    } catch (_) {
      AppLogger.w('Audit', 'Local agent-name resolution failed');
      return const {};
    }
  }

  Future<Map<String, String>> _resolveVaultNames() async {
    try {
      final vaults = switch (vaultListCubit.state) {
        VaultListLoaded(:final vaults) => vaults,
        _ => const <VaultEntity>[],
      };
      return {for (final v in vaults) v.id: v.name};
    } catch (_) {
      AppLogger.w('Audit', 'Local vault-name resolution failed');
      return const {};
    }
  }
}
