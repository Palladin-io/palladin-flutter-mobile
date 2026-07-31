import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/services/canonical_entry_detail_service.dart';
import '../../data/services/member_entry_list_service.dart';
import '../../data/services/member_sync_service.dart';
import '../../domain/entities/member_index_entry.dart';
import 'entry_archive_state.dart';

export 'entry_archive_state.dart';

/// Owns the runtime-only Archive projection for one unlocked Vault.
class EntryArchiveCubit extends Cubit<EntryArchiveState> {
  EntryArchiveCubit({
    required this.vaultId,
    required MemberIndexReader index,
    required MemberEntryListLoader sync,
    required EntryArchiveRestorer restorer,
    this.maximumEntries = 20000,
  }) : _index = index,
       _sync = sync,
       _restorer = restorer,
       super(const EntryArchiveInitial());

  final String vaultId;
  final MemberIndexReader _index;
  final MemberEntryListLoader _sync;
  final EntryArchiveRestorer _restorer;
  final int maximumEntries;

  void loadLocal() => _emitAuthoritative(_index.entries(vaultId));

  void search(String value) {
    final current = state;
    if (current is! EntryArchiveLoaded) return;
    emit(current.copyWith(query: String.fromCharCodes(value.runes.take(200))));
  }

  void filterType(int? value) {
    final current = state;
    if (current is EntryArchiveLoaded) {
      emit(current.copyWith(typeFilter: value));
    }
  }

  void sortBy(EntryArchiveSort value) {
    final current = state;
    if (current is EntryArchiveLoaded) emit(current.copyWith(sort: value));
  }

  Future<void> restore({
    required String entryId,
    required Uint8List memberPrivateKey,
  }) async {
    final current = state;
    if (current is! EntryArchiveLoaded ||
        current.restoringIds.contains(entryId)) {
      return;
    }
    final matches = current.entries.where((entry) => entry.entryId == entryId);
    if (matches.length != 1 || matches.single.corrupt) {
      _emitTransient(CanonicalEntryDetailError.corrupt);
      return;
    }
    final pending = {...current.restoringIds, entryId};
    emit(current.copyWith(restoringIds: pending, transientError: null));
    try {
      await _restorer.restoreArchived(
        vaultId: vaultId,
        archived: matches.single,
        memberPrivateKey: memberPrivateKey,
      );
      final authoritative = await _sync.load(
        vaultId: vaultId,
        memberPrivateKey: memberPrivateKey,
      );
      _emitAuthoritative(authoritative);
    } on CanonicalEntryDetailException catch (error) {
      _emitTransient(error.kind);
    } on FormatException {
      _emitTransient(CanonicalEntryDetailError.corrupt);
    } catch (_) {
      _emitTransient(CanonicalEntryDetailError.network);
    }
  }

  void lock() => emit(const EntryArchiveLocked());

  void _emitAuthoritative(List<MemberIndexEntry> source) {
    if (source.length > maximumEntries) {
      emit(const EntryArchiveError(CanonicalEntryDetailError.corrupt));
      return;
    }
    final archived = source
        .where((entry) => entry.state == MemberEntryState.archived)
        .toList(growable: false);
    emit(EntryArchiveLoaded(entries: archived));
  }

  void _emitTransient(CanonicalEntryDetailError kind) {
    final current = state;
    if (current is! EntryArchiveLoaded) {
      emit(EntryArchiveError(kind));
      return;
    }
    emit(
      current.copyWith(
        restoringIds: const {},
        transientError: kind,
        transientErrorTick: current.transientErrorTick + 1,
      ),
    );
  }
}
