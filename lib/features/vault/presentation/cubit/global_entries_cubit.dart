import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/services/member_entry_list_service.dart';
import '../../data/services/local_current_entry_service.dart';
import '../../data/services/canonical_entry_detail_service.dart';
import '../../domain/entities/entry_entity.dart';
import '../../data/services/member_sync_service.dart';
import '../../domain/entities/member_index_entry.dart';
import '../../domain/entities/vault_entity.dart';

/// A presentation-only join. Secrets and unwrapped keys never enter this row.
final class GlobalEntryRow {
  const GlobalEntryRow({required this.vault, required this.entry});

  final VaultEntity vault;
  final MemberIndexEntry entry;

  (String, String) get identity => (vault.id, entry.entryId);

  EntryEntity toEntryEntity() {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final domain = entry.autofillDomains.firstOrNull;
    return EntryEntity(
      id: entry.entryId,
      vaultId: vault.id,
      label: entry.memberLabel,
      type: EntryType.values.elementAtOrNull(entry.entryType) ?? EntryType.key,
      icon: entry.iconReference,
      createdAt: epoch,
      updatedAt: epoch,
      urlDomain: domain == null
          ? null
          : Uri.tryParse(
              domain.contains('://') ? domain : 'https://$domain',
            )?.host,
      currentRevision: entry.revision,
      currentKeyVersion: entry.currentKeyVersion,
      lifecycleState: entry.state,
      corrupt: entry.corrupt,
    );
  }
}

final class GlobalEntriesState {
  const GlobalEntriesState({
    this.rows = const [],
    this.loading = false,
    this.failedVaultIds = const {},
    this.expandedEntries = const {},
    this.revealedEntries = const {},
  });

  final List<GlobalEntryRow> rows;
  final bool loading;
  final Set<String> failedVaultIds;
  final Set<(String, String)> expandedEntries;
  final Map<(String, String), CanonicalEntrySnapshot> revealedEntries;

  List<GlobalEntryRow> filter({
    String query = '',
    Set<String> vaultIds = const {},
    Set<int> types = const {},
    bool descending = false,
  }) {
    final needle = query.trim().toLowerCase();
    final result = rows.where((row) {
      if (vaultIds.isNotEmpty && !vaultIds.contains(row.vault.id)) return false;
      if (types.isNotEmpty && !types.contains(row.entry.entryType)) {
        return false;
      }
      return needle.isEmpty ||
          [
            row.entry.memberLabel,
            ...row.entry.searchFields,
          ].any((value) => value.toLowerCase().contains(needle));
    }).toList();
    result.sort((a, b) {
      final label = a.entry.memberLabel.toLowerCase().compareTo(
        b.entry.memberLabel.toLowerCase(),
      );
      if (label != 0) return descending ? -label : label;
      final vault = a.vault.id.compareTo(b.vault.id);
      return vault != 0 ? vault : a.entry.entryId.compareTo(b.entry.entryId);
    });
    return result;
  }
}

/// Reads the authoritative runtime index on every update, including removal.
/// Loading is sequential and shares the existing loader's per-Vault flights.
final class GlobalEntriesCubit extends Cubit<GlobalEntriesState> {
  GlobalEntriesCubit({
    required MemberIndexReader index,
    required MemberEntryListLoader loader,
    required Stream<String> indexUpdates,
    required LocalCurrentEntryService localEntries,
  }) : _index = index,
       _localEntries = localEntries,
       _loader = loader,
       super(const GlobalEntriesState()) {
    _updates = indexUpdates.listen((_) {
      _clearReveals();
      _publish();
    });
  }

  final MemberIndexReader _index;
  final LocalCurrentEntryService _localEntries;
  final _expanded = <(String, String)>{};
  final _revealed = <(String, String), CanonicalEntrySnapshot>{};
  final _pendingKeys = <(String, String), Uint8List>{};
  final MemberEntryListLoader _loader;
  late final StreamSubscription<String> _updates;
  List<VaultEntity> _vaults = const [];
  Set<String> _failed = {};
  bool _loading = false;
  bool _locked = true;
  int _generation = 0;
  Uint8List? _keyCopy;

  void replaceVaults(List<VaultEntity> vaults) {
    if (_locked || isClosed) return;
    _clearReveals();
    _vaults = List.unmodifiable(vaults);
    _failed = _failed.intersection(vaults.map((vault) => vault.id).toSet());
    _publish();
  }

  Future<void> load(List<VaultEntity> vaults, Uint8List privateKey) async {
    if (isClosed) return;
    final generation = ++_generation;
    _clearReveals();
    _wipeKey();
    _locked = false;
    _vaults = List.unmodifiable(vaults);
    _failed = {};
    _loading = true;
    final key = Uint8List.fromList(privateKey);
    _keyCopy = key;
    _publish();
    try {
      for (final vault in vaults) {
        if (!_current(generation)) return;
        // A Vault removed while another sync is pending must not be loaded
        // again or reintroduced by this older traversal.
        if (!_vaults.any((current) => current.id == vault.id)) continue;
        try {
          await _loader.load(vaultId: vault.id, memberPrivateKey: key);
        } catch (_) {
          if (!_current(generation)) return;
          _failed.add(vault.id);
        }
        if (!_current(generation)) return;
        _publish();
      }
    } finally {
      key.fillRange(0, key.length, 0);
      if (identical(_keyCopy, key)) _keyCopy = null;
      if (_current(generation)) {
        _loading = false;
        _publish();
      }
    }
  }

  bool _current(int generation) =>
      !isClosed && !_locked && generation == _generation;

  void _publish() {
    if (_locked || isClosed) return;
    final rows = <GlobalEntryRow>[];
    for (final vault in _vaults) {
      for (final entry in _index.entries(vault.id)) {
        if (entry.state != MemberEntryState.active || entry.corrupt) continue;
        rows.add(GlobalEntryRow(vault: vault, entry: entry));
      }
    }
    emit(
      GlobalEntriesState(
        rows: List.unmodifiable(rows),
        loading: _loading,
        failedVaultIds: Set.unmodifiable(_failed),
        expandedEntries: Set.unmodifiable(_expanded),
        revealedEntries: Map.unmodifiable(_revealed),
      ),
    );
  }

  /// The application owns cancellation of shared sync; this view only drops
  /// its own state and makes late completions unable to republish it.
  void lock() {
    _generation++;
    _clearReveals();
    _locked = true;
    _loading = false;
    _vaults = const [];
    _failed = {};
    _wipeKey();
    if (!isClosed) emit(const GlobalEntriesState());
  }

  Future<bool> toggleReveal(GlobalEntryRow row, Uint8List privateKey) async {
    if (_locked || isClosed) return true;
    if (EntryType.values.elementAtOrNull(row.entry.entryType) == null) {
      return false;
    }
    final id = row.identity;
    if (_expanded.remove(id)) {
      _pendingKeys.remove(id)?.fillRange(0, 32, 0);
      _revealed.remove(id)?.clear();
      _publish();
      return true;
    }
    if (privateKey.length != 32 ||
        !state.rows.any(
          (current) =>
              current.identity == id &&
              current.entry.revision == row.entry.revision,
        )) {
      return false;
    }
    final generation = _generation;
    final key = Uint8List.fromList(privateKey);
    _pendingKeys[id] = key;
    _expanded.add(id);
    _publish();
    bool current() => _current(generation) && identical(_pendingKeys[id], key);
    CanonicalEntrySnapshot? snapshot;
    try {
      snapshot = await _localEntries.reveal(
        expected: row.toEntryEntity(),
        memberPrivateKey: key,
      );
      if (!current()) return true;
      _revealed[id] = snapshot;
      snapshot = null;
      _publish();
      return true;
    } catch (_) {
      if (!current()) return true;
      _expanded.remove(id);
      _publish();
      return false;
    } finally {
      snapshot?.clear();
      key.fillRange(0, key.length, 0);
      if (identical(_pendingKeys[id], key)) _pendingKeys.remove(id);
    }
  }

  void clearReveals() {
    _clearReveals();
    _publish();
  }

  void _clearReveals() {
    for (final key in _pendingKeys.values) {
      key.fillRange(0, key.length, 0);
    }
    _pendingKeys.clear();
    for (final snapshot in _revealed.values) {
      snapshot.clear();
    }
    _revealed.clear();
    _expanded.clear();
  }

  void _wipeKey() {
    final key = _keyCopy;
    _keyCopy = null;
    key?.fillRange(0, key.length, 0);
  }

  @override
  Future<void> close() async {
    lock();
    await _updates.cancel();
    await super.close();
  }
}
