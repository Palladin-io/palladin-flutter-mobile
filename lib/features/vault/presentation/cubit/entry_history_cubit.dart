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
    this.loadingMore = false,
  });

  final EntryHistoryStatus status;
  final List<EntryHistoryVersion> items;
  final String? nextCursor;
  final String? selectedRevision;
  final CanonicalEntryHistorySnapshot? selected;
  final EntryEntity? updatedEntry;
  final EntryHistoryFailure? failure;
  final bool loadingMore;
}

/// Lazy, bounded state for the Entry History tab.
class EntryHistoryCubit extends Cubit<EntryHistoryState> {
  EntryHistoryCubit(this._service) : super(const EntryHistoryState());

  final EntryHistoryService _service;
  bool _opened = false;
  int _operationEpoch = 0;

  Future<void> open(EntryEntity entry) async {
    if (_opened) return;
    _opened = true;
    final epoch = ++_operationEpoch;
    emit(const EntryHistoryState(status: EntryHistoryStatus.loading));
    try {
      final page = await _service.loadPage(entry);
      if (epoch != _operationEpoch || isClosed) return;
      emit(
        EntryHistoryState(
          status: EntryHistoryStatus.ready,
          items: page.items,
          nextCursor: page.nextCursor,
        ),
      );
    } catch (_) {
      if (epoch != _operationEpoch || isClosed) return;
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
    _operationEpoch += 1;
    _opened = false;
    _clearSelected();
    emit(const EntryHistoryState());
  }

  Future<void> loadMore(EntryEntity entry) async {
    final current = state;
    final cursor = current.nextCursor;
    if (cursor == null ||
        current.status != EntryHistoryStatus.ready ||
        current.loadingMore) {
      return;
    }
    if (current.items.length >= EntryHistoryService.maximumLoadedVersions) {
      return;
    }
    final epoch = ++_operationEpoch;
    emit(
      EntryHistoryState(
        status: EntryHistoryStatus.ready,
        items: current.items,
        nextCursor: cursor,
        selectedRevision: current.selectedRevision,
        selected: current.selected,
        loadingMore: true,
      ),
    );
    try {
      final page = await _service.loadPage(entry, beforeRevision: cursor);
      if (epoch != _operationEpoch || isClosed) return;
      if (page.nextCursor == cursor) {
        throw const FormatException('Repeated cursor');
      }
      final combined = [...current.items, ...page.items];
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
          selectedRevision: current.selectedRevision,
          selected: current.selected,
        ),
      );
    } catch (_) {
      if (epoch != _operationEpoch || isClosed) return;
      emit(
        EntryHistoryState(
          status: EntryHistoryStatus.ready,
          items: current.items,
          nextCursor: cursor,
          selectedRevision: current.selectedRevision,
          selected: current.selected,
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
    final epoch = ++_operationEpoch;
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
      if (epoch != _operationEpoch || isClosed) {
        selected.clear();
        return;
      }
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
      if (epoch != _operationEpoch || isClosed) return;
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
    final epoch = ++_operationEpoch;
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
      if (epoch != _operationEpoch || isClosed) return;
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
      if (epoch != _operationEpoch || isClosed) return;
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
    final wasOpening = state.status == EntryHistoryStatus.loading;
    _operationEpoch += 1;
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
    if (!keepItems || wasOpening) {
      _opened = false;
    }
    if (!keepItems) {
      _service.clearSessionCache();
    }
  }

  void hideSelected() {
    _operationEpoch += 1;
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
    _operationEpoch += 1;
    _clearSelected();
    return super.close();
  }
}
