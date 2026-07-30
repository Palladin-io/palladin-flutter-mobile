import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/search_result_entity.dart';
import '../../domain/entities/recent_entry_entity.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../../domain/repositories/local_search_repository.dart';
import 'search_session_controller.dart';
import 'search_state.dart';

/// Drives the dashboard global-search autocomplete.
///
/// Debounces keystrokes by [_debounce] so a fast typist triggers a single
/// backend call. Queries shorter than [_minQueryLength] characters short-
/// circuit to [SearchIdle] (the dashboard shows its normal content). A
/// fresh instance is created per page mount (registered as a factory), so
/// no stale results leak across visits.
class SearchCubit extends Cubit<SearchState> {
  SearchCubit({
    required DashboardRepository repository,
    LocalSearchRepository? localRepository,
    required AnalyticsService analytics,
    SearchSessionController? sessionController,
  }) : _repository = repository,
       _localRepository =
           localRepository ?? const _EmptyLocalSearchRepository(),
       _analytics = analytics,
       _sessionController = sessionController ?? SearchSessionController(),
       super(const SearchIdle()) {
    _sessionController.attach(this);
  }

  final DashboardRepository _repository;
  final LocalSearchRepository _localRepository;
  final AnalyticsService _analytics;
  final SearchSessionController _sessionController;

  static const Duration _debounce = Duration(milliseconds: 250);
  static const int _minQueryLength = 2;
  static const int _limit = 10;
  static const int _combinedLimit = _limit * 2;

  Timer? _debounceTimer;
  CancelToken? _remoteCancellation;
  Future<void>? _localPreparation;

  /// Starts rebuilding the runtime-only local index for Home search.
  /// No key reference is retained after the returned operation completes.
  void prepare(Uint8List memberPrivateKey) {
    _localPreparation = _localRepository
        .prepare(memberPrivateKey)
        .then(
          (_) {},
          onError: (Object _, StackTrace stackTrace) {
            AppLogger.w('Search', 'Local search index unavailable');
          },
        );
  }

  /// Monotonic token identifying the latest intended query. Every call that
  /// changes what the user is asking for (a new [_run], a reset, or a
  /// short-circuit to idle) bumps it, so a slow in-flight request whose token
  /// is stale drops its result instead of clobbering fresher state.
  int _queryGeneration = 0;

  /// Handles a change to the search field. Debounces by [_debounce]; a
  /// query shorter than [_minQueryLength] resets to [SearchIdle] immediately.
  void query(String q) {
    _debounceTimer?.cancel();

    final trimmed = q.trim();
    if (trimmed.length < _minQueryLength) {
      // Invalidate any in-flight request so its late result can't overwrite
      // the idle state we're about to show.
      _queryGeneration++;
      emit(const SearchIdle());
      return;
    }

    _debounceTimer = Timer(_debounce, () => _run(trimmed));
  }

  Future<void> _run(String q) async {
    final token = ++_queryGeneration;
    _remoteCancellation?.cancel();
    final cancellation = CancelToken();
    _remoteCancellation = cancellation;
    final localFuture = () async {
      await _localPreparation;
      return _localRepository.search(q, limit: _limit);
    }();
    final remoteFuture =
        Future<List<SearchResultEntity>>.sync(
          () => _repository.globalSearch(
            q,
            limit: _limit,
            cancelToken: cancellation,
          ),
        ).then<({List<SearchResultEntity>? results, Object? error})>(
          (results) => (results: results, error: null),
          onError: (Object error, StackTrace _) =>
              (results: null, error: error),
        );
    final local = await localFuture;
    if (token != _queryGeneration || isClosed) return;
    emit(
      local.isEmpty
          ? const SearchLoading()
          : SearchResults(local, remotePending: true),
    );
    try {
      final outcome = await remoteFuture;
      final error = outcome.error;
      if (error != null) throw error;
      final remote = outcome.results!;
      // A newer query (or a reset) superseded this request while it was in
      // flight — drop the stale result.
      if (token != _queryGeneration || isClosed) return;
      final results = _merge(local, remote);
      emit(results.isEmpty ? const SearchEmpty() : SearchResults(results));
    } on DioException catch (error) {
      if (CancelToken.isCancel(error) ||
          token != _queryGeneration ||
          isClosed) {
        return;
      }
      if (local.isNotEmpty) {
        emit(SearchResults(local, remoteFailed: true));
      } else {
        AppLogger.w('Search', 'Administrative search unavailable');
        emit(const SearchError());
      }
    } catch (_) {
      if (token != _queryGeneration || isClosed) return;
      if (local.isNotEmpty) {
        emit(SearchResults(local, remoteFailed: true));
      } else {
        AppLogger.w('Search', 'Administrative search unavailable');
        emit(const SearchError());
      }
    }
  }

  static List<SearchResultEntity> _merge(
    List<SearchResultEntity> local,
    List<SearchResultEntity> remote,
  ) {
    final seen = <String>{};
    return <SearchResultEntity>[...local, ...remote]
        .where((result) => seen.add(result.deduplicationKey))
        .take(_combinedLimit)
        .toList(growable: false);
  }

  /// Fires the analytics event for a tapped result. Navigation is performed
  /// by the caller (which owns the router / BuildContext).
  void selectResult(SearchResultEntity result) {
    _analytics.capture(
      'dashboard',
      'search-result-selected',
      properties: {'type': result.type.name},
    );
  }

  /// Cancels any pending query and returns to the idle (dashboard) state.
  void reset() {
    _debounceTimer?.cancel();
    // Invalidate any in-flight request so it can't re-populate results after
    // the user has navigated away / cleared the field.
    _queryGeneration++;
    _remoteCancellation?.cancel();
    _remoteCancellation = null;
    emit(const SearchIdle());
  }

  /// Clears query intent/results and cancels transport on lock/background.
  void securityReset() => reset();

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    _remoteCancellation?.cancel();
    _sessionController.detach(this);
    return super.close();
  }
}

final class _EmptyLocalSearchRepository implements LocalSearchRepository {
  const _EmptyLocalSearchRepository();

  @override
  Future<void> prepare(Uint8List memberPrivateKey) async {}

  @override
  List<SearchResultEntity> search(String query, {int limit = 10}) => const [];

  @override
  List<RecentEntryEntity> recentEntries({int limit = 5}) => const [];
}
