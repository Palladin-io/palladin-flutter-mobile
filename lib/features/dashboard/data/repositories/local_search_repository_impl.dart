import 'dart:typed_data';

import '../../../vault/data/services/member_entry_list_service.dart';
import '../../../vault/data/services/member_sync_service.dart';
import '../../../vault/domain/entities/member_index_entry.dart';
import '../../../vault/domain/entities/vault_performance_budget.dart';
import '../../../vault/presentation/cubit/vault_list_cubit.dart';
import '../../domain/entities/recent_entry_entity.dart';
import '../../domain/entities/search_result_entity.dart';
import '../../domain/repositories/local_search_repository.dart';

/// Bounded search facade over unlocked in-memory Vault metadata/MemberIndex.
final class LocalSearchRepositoryImpl implements LocalSearchRepository {
  LocalSearchRepositoryImpl({
    required VaultListCubit vaults,
    required MemberIndexReader memberIndex,
    required MemberEntryListLoader entryLoader,
    this.maximumCandidates = VaultPerformanceBudget.maximumIndexedEntries,
  }) : _vaults = vaults,
       _memberIndex = memberIndex,
       _entryLoader = entryLoader;

  final VaultListCubit _vaults;
  final MemberIndexReader _memberIndex;
  final MemberEntryListLoader _entryLoader;
  final int maximumCandidates;

  @override
  Future<void> prepare(Uint8List memberPrivateKey) async {
    if (memberPrivateKey.length != 32) {
      throw const FormatException('Member private key must be 32 bytes');
    }
    await _vaults.loadIfNeeded(memberPrivateKey);
    final state = _vaults.state;
    if (state is! VaultListLoaded) return;
    for (final vault in state.vaults) {
      await _entryLoader.load(
        vaultId: vault.id,
        memberPrivateKey: memberPrivateKey,
      );
    }
  }

  @override
  List<SearchResultEntity> search(String query, {int limit = 10}) {
    if (limit < 1 || limit > 50) throw ArgumentError.value(limit, 'limit');
    final normalized = _normalize(query);
    if (normalized.length < 2) return const [];
    final state = _vaults.state;
    if (state is! VaultListLoaded) return const [];

    final vaultHits = <({int rank, VaultSearchResult result})>[];
    final entryHits = <({int rank, EntrySearchResult result})>[];
    var entryCandidates = 0;
    for (final vault in state.vaults) {
      final vaultRank = _rank(vault.name, normalized);
      if (vaultRank != null) {
        vaultHits.add((
          rank: vaultRank,
          result: VaultSearchResult(
            vaultId: vault.id,
            displayName: vault.name,
            iconReference: vault.icon,
          ),
        ));
      }
      for (final entry in _memberIndex.entries(vault.id)) {
        if (++entryCandidates > maximumCandidates) break;
        if (entry.corrupt || entry.state != MemberEntryState.active) continue;
        final labelRank = _rank(entry.memberLabel, normalized);
        final fieldsMatch = entry.searchFields.any(
          (field) => _normalize(field).contains(normalized),
        );
        if (labelRank == null && !fieldsMatch) continue;
        entryHits.add((
          rank: labelRank ?? 2,
          result: EntrySearchResult(
            vaultId: vault.id,
            entryId: entry.entryId,
            displayName: entry.memberLabel,
            vaultName: vault.name,
            entryType: entry.entryType,
            iconReference: entry.iconReference,
          ),
        ));
      }
      if (entryCandidates > maximumCandidates) break;
    }
    int compare<T extends SearchResultEntity>(
      ({int rank, T result}) left,
      ({int rank, T result}) right,
    ) {
      final rank = left.rank.compareTo(right.rank);
      if (rank != 0) return rank;
      final name = left.result.name.toLowerCase().compareTo(
        right.result.name.toLowerCase(),
      );
      return name != 0
          ? name
          : left.result.deduplicationKey.compareTo(
              right.result.deduplicationKey,
            );
    }

    vaultHits.sort(compare);
    entryHits.sort(compare);
    return <SearchResultEntity>[
      ...vaultHits.map((hit) => hit.result),
      ...entryHits.map((hit) => hit.result),
    ].take(limit).toList(growable: false);
  }

  @override
  List<RecentEntryEntity> recentEntries({int limit = 5}) {
    if (limit < 1 || limit > 20) throw ArgumentError.value(limit, 'limit');
    final state = _vaults.state;
    if (state is! VaultListLoaded) return const [];
    final results = <RecentEntryEntity>[];
    for (final vault in state.vaults) {
      for (final entry in _memberIndex.entries(vault.id)) {
        if (entry.corrupt || entry.state != MemberEntryState.active) continue;
        results.add(
          RecentEntryEntity(
            id: entry.entryId,
            label: entry.memberLabel,
            vaultId: vault.id,
            vaultName: vault.name,
            typeWire: entry.entryType,
            icon: entry.iconReference,
            updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
            createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );
        if (results.length == limit) return List.unmodifiable(results);
      }
    }
    return List.unmodifiable(results);
  }

  static int? _rank(String value, String query) {
    final normalized = _normalize(value);
    if (normalized.startsWith(query)) return 0;
    if (normalized.contains(query)) return 1;
    return null;
  }

  static String _normalize(String value) => value.trim().toLowerCase();
}
