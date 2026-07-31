import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/audit_log_entry.dart';
import '../../domain/exceptions/audit_exceptions.dart';
import '../../domain/repositories/audit_repository.dart';
import '../audit_presentation_resolver.dart';
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
    required this.presentationResolver,
    required AuditLogScope scope,
    this.vaultId,
    this.maximumLoadedEntries = 2000,
    this.entryNameRefreshDelay = const Duration(milliseconds: 250),
  }) : super(AuditLogState(scope: scope));

  final AuditRepository auditRepository;
  final AuditPresentationResolver presentationResolver;
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
          entries: presentationResolver.applyNames(accepted, scopedNames),
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
    final resolvedEntries = presentationResolver.applyNames(
      state.entries,
      retained,
    );
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
      final appended = presentationResolver
          .applyNames(
            page.entries.where((entry) => existingIds.add(entry.id)).toList(),
            mergedNames,
          )
          .take(remaining)
          .toList(growable: false);
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

  Future<AuditPresentationNames> _resolveNames(List<AuditLogEntry> page) =>
      presentationResolver.resolveNames(
        page,
        scopedVaultId: state.scope == AuditLogScope.vault ? vaultId : null,
      );

  AuditPresentationNames _namesFromState() => AuditPresentationNames(
    agents: state.agentNames,
    vaults: state.vaultNames,
    entries: state.entryNames,
    members: state.memberNames,
  );

  AuditPresentationNames _mergeNames(
    AuditPresentationNames current,
    AuditPresentationNames page,
  ) => current.merge(page);

  AuditPresentationNames _retainNamesForEntries(
    AuditPresentationNames names,
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
    return AuditPresentationNames(
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
}
