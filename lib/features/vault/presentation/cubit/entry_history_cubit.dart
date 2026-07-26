import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/services/canonical_entry_detail_service.dart';
import '../../data/services/entry_history_service.dart';
import '../../domain/entities/entry_entity.dart';

enum EntryHistoryStatus { initial, loading, ready, revealing, restoring, error }

class EntryHistoryState {
  const EntryHistoryState({
    this.status = EntryHistoryStatus.initial,
    this.items = const [],
    this.nextCursor,
    this.selectedRevision,
    this.selected,
    this.updatedEntry,
  });

  final EntryHistoryStatus status;
  final List<EntryHistoryVersion> items;
  final String? nextCursor;
  final String? selectedRevision;
  final CanonicalEntryHistorySnapshot? selected;
  final EntryEntity? updatedEntry;
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
      emit(const EntryHistoryState(status: EntryHistoryStatus.error));
    }
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
      clearSensitiveState(keepItems: true);
      emit(
        EntryHistoryState(status: EntryHistoryStatus.error, items: state.items),
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
          status: EntryHistoryStatus.error,
          items: state.items,
          nextCursor: state.nextCursor,
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
          updatedEntry: updated,
        ),
      );
    } catch (_) {
      _clearSelected();
      emit(
        EntryHistoryState(status: EntryHistoryStatus.error, items: state.items),
      );
    } finally {
      privateKey.fillRange(0, privateKey.length, 0);
    }
  }

  void clearSensitiveState({bool keepItems = false}) {
    _clearSelected();
    emit(EntryHistoryState(items: keepItems ? state.items : const []));
    if (!keepItems) _opened = false;
  }

  void _clearSelected() => state.selected?.clear();

  @override
  Future<void> close() {
    _clearSelected();
    return super.close();
  }
}
