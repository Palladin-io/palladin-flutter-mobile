import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/services/canonical_entry_detail_service.dart';
import '../../data/services/entry_history_service.dart';
import '../../domain/entities/entry_entity.dart';

enum EntryHistoryStatus { initial, loading, ready, revealing, restoring, error }

enum EntryHistoryFailure { load, loadMore, reveal, restore }

class EntryHistoryState {
  const EntryHistoryState({
    this.status = EntryHistoryStatus.initial,
    this.items = const [],
    this.nextCursor,
    this.selectedRevision,
    this.selected,
    this.updatedEntry,
    this.failure,
  });

  final EntryHistoryStatus status;
  final List<EntryHistoryVersion> items;
  final String? nextCursor;
  final String? selectedRevision;
  final CanonicalEntryHistorySnapshot? selected;
  final EntryEntity? updatedEntry;
  final EntryHistoryFailure? failure;
}

/// Lazy, bounded state for the Entry History tab.
class EntryHistoryCubit extends Cubit<EntryHistoryState> {
  EntryHistoryCubit(this._service) : super(const EntryHistoryState());

  final EntryHistoryService _service;
  bool _opened = false;

  Future<void> open(EntryEntity entry) async {
    if (_opened) return;
    _opened = true;
    emit(const EntryHistoryState(status: EntryHistoryStatus.loading));
    try {
      final page = await _service.loadPage(entry);
      emit(
        EntryHistoryState(
          status: EntryHistoryStatus.ready,
          items: page.items,
          nextCursor: page.nextCursor,
        ),
      );
    } catch (_) {
      _opened = false;
      emit(
        const EntryHistoryState(
          status: EntryHistoryStatus.error,
          failure: EntryHistoryFailure.load,
        ),
      );
    }
  }

  void invalidate() {
    _opened = false;
    _clearSelected();
    emit(const EntryHistoryState());
  }

  Future<void> loadMore(EntryEntity entry) async {
    final cursor = state.nextCursor;
    if (cursor == null || state.status != EntryHistoryStatus.ready) return;
    if (state.items.length >= EntryHistoryService.maximumLoadedVersions) return;
    try {
      final page = await _service.loadPage(entry, beforeRevision: cursor);
      if (page.nextCursor == cursor) {
        throw const FormatException('Repeated cursor');
      }
      final combined = [...state.items, ...page.items];
      emit(
        EntryHistoryState(
          status: EntryHistoryStatus.ready,
          items: combined
              .take(EntryHistoryService.maximumLoadedVersions)
              .toList(),
          nextCursor:
              combined.length >= EntryHistoryService.maximumLoadedVersions
              ? null
              : page.nextCursor,
        ),
      );
    } catch (_) {
      emit(
        EntryHistoryState(
          status: EntryHistoryStatus.ready,
          items: state.items,
          nextCursor: state.nextCursor,
          failure: EntryHistoryFailure.loadMore,
        ),
      );
    }
  }

  Future<void> reveal({
    required EntryEntity entry,
    required EntryHistoryVersion version,
    required Uint8List privateKey,
  }) async {
    _clearSelected();
    emit(
      EntryHistoryState(
        status: EntryHistoryStatus.revealing,
        items: state.items,
        nextCursor: state.nextCursor,
        selectedRevision: version.revision,
      ),
    );
    try {
      final selected = await _service.reveal(
        entry: entry,
        version: version,
        privateKey: privateKey,
      );
      emit(
        EntryHistoryState(
          status: EntryHistoryStatus.ready,
          items: state.items,
          nextCursor: state.nextCursor,
          selectedRevision: version.revision,
          selected: selected,
        ),
      );
    } catch (_) {
      _clearSelected();
      emit(
        EntryHistoryState(
          status: EntryHistoryStatus.ready,
          items: state.items,
          nextCursor: state.nextCursor,
          failure: EntryHistoryFailure.reveal,
        ),
      );
    } finally {
      privateKey.fillRange(0, privateKey.length, 0);
    }
  }

  Future<void> restore({
    required EntryEntity entry,
    required Uint8List privateKey,
  }) async {
    final selected = state.selected;
    try {
      if (selected == null) return;
      emit(
        EntryHistoryState(
          status: EntryHistoryStatus.restoring,
          items: state.items,
          nextCursor: state.nextCursor,
          selectedRevision: state.selectedRevision,
          selected: selected,
        ),
      );
      final updated = await _service.restore(
        entry: entry,
        selected: selected,
        privateKey: privateKey,
      );
      _clearSelected();
      emit(
        EntryHistoryState(
          status: EntryHistoryStatus.ready,
          items: state.items,
          nextCursor: state.nextCursor,
          updatedEntry: updated,
        ),
      );
    } catch (_) {
      _clearSelected();
      emit(
        EntryHistoryState(
          status: EntryHistoryStatus.ready,
          items: state.items,
          nextCursor: state.nextCursor,
          failure: EntryHistoryFailure.restore,
        ),
      );
    } finally {
      privateKey.fillRange(0, privateKey.length, 0);
    }
  }

  void clearSensitiveState({bool keepItems = false}) {
    _clearSelected();
    emit(
      EntryHistoryState(
        status: keepItems
            ? EntryHistoryStatus.ready
            : EntryHistoryStatus.initial,
        items: keepItems ? state.items : const [],
        nextCursor: keepItems ? state.nextCursor : null,
      ),
    );
    if (!keepItems) {
      _opened = false;
      _service.clearSessionCache();
    }
  }

  void hideSelected() {
    _clearSelected();
    emit(
      EntryHistoryState(
        status: EntryHistoryStatus.ready,
        items: state.items,
        nextCursor: state.nextCursor,
      ),
    );
  }

  void _clearSelected() => state.selected?.clear();

  @override
  Future<void> close() {
    _clearSelected();
    return super.close();
  }
}
