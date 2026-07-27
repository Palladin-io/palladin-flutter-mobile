import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/datasources/entry_remote_datasource.dart';
import '../../data/services/canonical_entry_detail_service.dart';
import '../../data/services/member_entry_list_service.dart';
import '../../data/services/member_sync_service.dart';
import '../../domain/entities/member_index_entry.dart';

sealed class RecentlyDeletedState {
  const RecentlyDeletedState();
}

final class RecentlyDeletedLoading extends RecentlyDeletedState {
  const RecentlyDeletedLoading();
}

final class RecentlyDeletedLocked extends RecentlyDeletedState {
  const RecentlyDeletedLocked();
}

final class RecentlyDeletedError extends RecentlyDeletedState {
  const RecentlyDeletedError(this.kind);
  final CanonicalEntryDetailError kind;
}

final class RecentlyDeletedItem {
  const RecentlyDeletedItem({
    required this.entryId,
    required this.deletedAt,
    required this.purgeAt,
    this.presentation,
  });

  final String entryId;
  final DateTime deletedAt;
  final DateTime purgeAt;
  final MemberIndexEntry? presentation;
}

final class RecentlyDeletedLoaded extends RecentlyDeletedState {
  const RecentlyDeletedLoaded({
    required this.items,
    this.query = '',
    this.pendingIds = const {},
    this.transientError,
    this.errorTick = 0,
  });

  final List<RecentlyDeletedItem> items;
  final String query;
  final Set<String> pendingIds;
  final CanonicalEntryDetailError? transientError;
  final int errorTick;

  List<RecentlyDeletedItem> get visibleItems {
    final normalized = query.trim().toLowerCase();
    final result = items
        .where((item) {
          if (normalized.isEmpty) return true;
          final local = item.presentation;
          return (local != null &&
                  !local.corrupt &&
                  (local.memberLabel.toLowerCase().contains(normalized) ||
                      local.searchFields.any(
                        (field) => field.toLowerCase().contains(normalized),
                      ))) ||
              item.entryId.toLowerCase().contains(normalized);
        })
        .toList(growable: false);
    result.sort((left, right) {
      final deadline = left.purgeAt.compareTo(right.purgeAt);
      return deadline != 0 ? deadline : left.entryId.compareTo(right.entryId);
    });
    return result;
  }

  RecentlyDeletedLoaded copyWith({
    List<RecentlyDeletedItem>? items,
    String? query,
    Set<String>? pendingIds,
    Object? transientError = _unset,
    int? errorTick,
  }) => RecentlyDeletedLoaded(
    items: items ?? this.items,
    query: query ?? this.query,
    pendingIds: pendingIds ?? this.pendingIds,
    transientError: identical(transientError, _unset)
        ? this.transientError
        : transientError as CanonicalEntryDetailError?,
    errorTick: errorTick ?? this.errorTick,
  );

  static const _unset = Object();
}

/// Joins structural deletion metadata with local decrypted presentation.
class RecentlyDeletedCubit extends Cubit<RecentlyDeletedState> {
  RecentlyDeletedCubit({
    required this.vaultId,
    required EntryRemoteDatasource remote,
    required MemberIndexReader index,
    required MemberEntryListLoader sync,
    required EntryArchiveRestorer lifecycle,
    this.maximumEntries = 10000,
  }) : _remote = remote,
       _index = index,
       _sync = sync,
       _lifecycle = lifecycle,
       super(const RecentlyDeletedLoading());

  final String vaultId;
  final EntryRemoteDatasource _remote;
  final MemberIndexReader _index;
  final MemberEntryListLoader _sync;
  final EntryArchiveRestorer _lifecycle;
  final int maximumEntries;

  Future<void> load() async {
    emit(const RecentlyDeletedLoading());
    try {
      final local = {
        for (final entry in _index.entries(vaultId))
          if (entry.state == MemberEntryState.deleted) entry.entryId: entry,
      };
      final items = <RecentlyDeletedItem>[];
      final cursors = <String>{};
      String? cursor;
      do {
        final page = await _remote.listRecentlyDeleted(
          vaultId,
          cursor: cursor,
          pageSize: 100,
        );
        final rawItems = page['items'];
        if (rawItems is! List) throw const FormatException('Missing items');
        for (final raw in rawItems) {
          if (raw is! Map ||
              raw['id'] is! String ||
              raw['deletedAt'] is! String ||
              raw['retentionExpiresAt'] is! String ||
              !_isDeleted(raw['state'])) {
            throw const FormatException('Malformed Deleted item');
          }
          final deletedAt = DateTime.parse(raw['deletedAt'] as String).toUtc();
          final purgeAt = DateTime.parse(
            raw['retentionExpiresAt'] as String,
          ).toUtc();
          if (purgeAt.isBefore(deletedAt)) {
            throw const FormatException('Invalid retention deadline');
          }
          final entryId = raw['id'] as String;
          items.add(
            RecentlyDeletedItem(
              entryId: entryId,
              deletedAt: deletedAt,
              purgeAt: purgeAt,
              presentation: local[entryId],
            ),
          );
          if (items.length > maximumEntries) {
            throw const FormatException('Recently Deleted exceeds limit');
          }
        }
        final next = page['nextCursor'];
        if (next != null && (next is! String || !cursors.add(next))) {
          throw const FormatException('Invalid lifecycle cursor');
        }
        cursor = next as String?;
      } while (cursor != null);
      emit(RecentlyDeletedLoaded(items: items));
    } on CanonicalEntryDetailException catch (error) {
      emit(RecentlyDeletedError(error.kind));
    } catch (_) {
      emit(const RecentlyDeletedError(CanonicalEntryDetailError.corrupt));
    }
  }

  void search(String value) {
    final current = state;
    if (current is RecentlyDeletedLoaded) {
      emit(
        current.copyWith(query: String.fromCharCodes(value.runes.take(200))),
      );
    }
  }

  Future<void> restore(String entryId, Uint8List privateKey) async {
    final current = state;
    if (current is! RecentlyDeletedLoaded ||
        current.pendingIds.contains(entryId)) {
      return;
    }
    final matches = current.items.where((item) => item.entryId == entryId);
    final local = matches.length == 1 ? matches.single.presentation : null;
    if (local == null || local.corrupt) {
      _error(CanonicalEntryDetailError.notFound);
      return;
    }
    emit(current.copyWith(pendingIds: {...current.pendingIds, entryId}));
    try {
      await _lifecycle.restoreRecoverable(
        vaultId: vaultId,
        entry: local,
        memberPrivateKey: privateKey,
      );
      await _sync.load(vaultId: vaultId, memberPrivateKey: privateKey);
      await load();
    } on CanonicalEntryDetailException catch (error) {
      _error(error.kind);
    }
  }

  Future<void> purge(String entryId) async {
    final current = state;
    if (current is! RecentlyDeletedLoaded ||
        current.pendingIds.contains(entryId)) {
      return;
    }
    emit(current.copyWith(pendingIds: {...current.pendingIds, entryId}));
    try {
      await _lifecycle.purgeDeleted(vaultId: vaultId, entryId: entryId);
      await load();
    } on CanonicalEntryDetailException catch (error) {
      _error(error.kind);
    }
  }

  void lock() => emit(const RecentlyDeletedLocked());

  void _error(CanonicalEntryDetailError kind) {
    final current = state;
    if (current is RecentlyDeletedLoaded) {
      emit(
        current.copyWith(
          pendingIds: const {},
          transientError: kind,
          errorTick: current.errorTick + 1,
        ),
      );
    } else {
      emit(RecentlyDeletedError(kind));
    }
  }

  bool _isDeleted(Object? state) =>
      state == 3 || state == 'Deleted' || state == 'deleted';
}
