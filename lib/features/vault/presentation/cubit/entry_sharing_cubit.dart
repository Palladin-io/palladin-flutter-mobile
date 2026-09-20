import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/datasources/entry_sharing_remote_datasource.dart';
import '../../domain/entities/entry_share_list.dart';

final class EntrySharingState {
  const EntrySharingState({
    this.items = const [],
    this.nextCursor,
    this.loading = false,
    this.loadingMore = false,
    this.revokingId,
    this.failure,
    this.loaded = false,
  });
  final List<EntryShareListItem> items;
  final String? nextCursor, revokingId;
  final bool loading, loadingMore, loaded;
  final EntrySharingFailure? failure;
  bool get busy => loading || loadingMore || revokingId != null;
}

class EntrySharingCubit extends Cubit<EntrySharingState> {
  EntrySharingCubit({
    required EntrySharingRemoteDatasource remote,
    required this.vaultId,
    required this.entryId,
    required Future<EntrySharingSession?> Function() sessionReader,
  }) : _remote = remote,
       _sessionReader = sessionReader,
       super(const EntrySharingState());

  final EntrySharingRemoteDatasource _remote;
  final String vaultId, entryId;
  final Future<EntrySharingSession?> Function() _sessionReader;
  EntrySharingSession? _owner;
  CancelToken? _request;
  int _epoch = 0;

  Future<bool> _valid(int epoch, {bool bind = false}) async {
    if (isClosed || epoch != _epoch) return false;
    EntrySharingSession? session;
    try {
      session = await _sessionReader();
    } catch (_) {
      session = null;
    }
    if (isClosed || epoch != _epoch) return false;
    if (bind && _owner == null) _owner = session;
    if (session == null || session != _owner) {
      clear(failure: EntrySharingFailure.unavailable);
      return false;
    }
    return true;
  }

  Future<void> load({bool more = false}) async {
    if (isClosed || state.busy || (more && state.nextCursor == null)) return;
    final previous = state;
    final epoch = ++_epoch;
    final token = _request = CancelToken();
    emit(
      EntrySharingState(
        items: previous.items,
        nextCursor: previous.nextCursor,
        loaded: previous.loaded,
        loading: !more,
        loadingMore: more,
      ),
    );
    try {
      if (!await _valid(epoch, bind: true)) return;
      final page = await _remote.list(
        vaultId,
        entryId,
        cursor: more ? previous.nextCursor : null,
        cancelToken: token,
      );
      if (!await _valid(epoch)) return;
      final items = <String, EntryShareListItem>{
        if (more)
          for (final item in previous.items) item.shareId: item,
        for (final item in page.items) item.shareId: item,
      };
      emit(
        EntrySharingState(
          items: List.unmodifiable(items.values),
          nextCursor: page.nextCursor,
          loaded: true,
        ),
      );
    } catch (_) {
      if (!await _valid(epoch)) return;
      emit(
        EntrySharingState(
          items: previous.items,
          nextCursor: previous.nextCursor,
          loaded: previous.loaded,
          failure: more
              ? EntrySharingFailure.loadMore
              : EntrySharingFailure.load,
        ),
      );
    } finally {
      if (identical(_request, token)) _request = null;
    }
  }

  Future<bool> revoke(String shareId) async {
    if (isClosed ||
        state.busy ||
        !state.items.any((item) => item.shareId == shareId && item.canRevoke)) {
      return false;
    }
    final previous = state;
    final epoch = ++_epoch;
    final token = _request = CancelToken();
    emit(
      EntrySharingState(
        items: previous.items,
        nextCursor: previous.nextCursor,
        loaded: true,
        revokingId: shareId,
      ),
    );
    try {
      if (!await _valid(epoch)) return false;
      await _remote.revoke(vaultId, entryId, shareId, cancelToken: token);
      if (!await _valid(epoch)) return false;
      emit(const EntrySharingState());
      await load();
      return !isClosed &&
          _epoch == epoch + 1 &&
          state.failure != EntrySharingFailure.unavailable;
    } catch (_) {
      if (!await _valid(epoch)) return false;
      emit(
        EntrySharingState(
          items: previous.items,
          nextCursor: previous.nextCursor,
          loaded: true,
          failure: EntrySharingFailure.revoke,
        ),
      );
      return false;
    } finally {
      if (identical(_request, token)) _request = null;
    }
  }

  void clear({EntrySharingFailure? failure}) {
    _epoch++;
    _request?.cancel();
    _request = null;
    if (!isClosed) emit(EntrySharingState(failure: failure));
  }

  @override
  Future<void> close() {
    clear();
    return super.close();
  }
}
