import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/services/member_entry_list_service.dart';
import '../../data/services/member_sync_service.dart';
import '../../domain/entities/member_index_entry.dart';
import '../../domain/entities/vault_entity.dart';

/// A presentation-only join. Secrets and unwrapped keys never enter this row.
final class GlobalEntryRow {
  const GlobalEntryRow({required this.vault, required this.entry});

  final VaultEntity vault;
  final MemberIndexEntry entry;
}

final class GlobalEntriesState {
  const GlobalEntriesState({
    this.rows = const [],
    this.loading = false,
    this.failedVaultIds = const {},
  });

  final List<GlobalEntryRow> rows;
  final bool loading;
  final Set<String> failedVaultIds;

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
  }) : _index = index,
       _loader = loader,
       super(const GlobalEntriesState()) {
    _updates = indexUpdates.listen((_) => _publish());
  }

  final MemberIndexReader _index;
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
    _vaults = List.unmodifiable(vaults);
    _failed = _failed.intersection(vaults.map((vault) => vault.id).toSet());
    _publish();
  }

  Future<void> load(List<VaultEntity> vaults, Uint8List privateKey) async {
    if (isClosed) return;
    final generation = ++_generation;
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
      ),
    );
  }

  /// The application owns cancellation of shared sync; this view only drops
  /// its own state and makes late completions unable to republish it.
  void lock() {
    _generation++;
    _locked = true;
    _loading = false;
    _vaults = const [];
    _failed = {};
    _wipeKey();
    if (!isClosed) emit(const GlobalEntriesState());
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
