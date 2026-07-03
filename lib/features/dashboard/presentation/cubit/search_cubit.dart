import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/search_result_entity.dart';
import '../../domain/repositories/dashboard_repository.dart';
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
    required AnalyticsService analytics,
  })  : _repository = repository,
        _analytics = analytics,
        super(const SearchIdle());

  final DashboardRepository _repository;
  final AnalyticsService _analytics;

  static const Duration _debounce = Duration(milliseconds: 250);
  static const int _minQueryLength = 2;
  static const int _limit = 10;

  Timer? _debounceTimer;

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
    emit(const SearchLoading());
    try {
      final results = await _repository.globalSearch(q, limit: _limit);
      // A newer query (or a reset) superseded this request while it was in
      // flight — drop the stale result.
      if (token != _queryGeneration || isClosed) return;
      emit(results.isEmpty ? const SearchEmpty() : SearchResults(results));
    } catch (e, s) {
      if (token != _queryGeneration || isClosed) return;
      AppLogger.e('Search', 'Global search failed', error: e, stackTrace: s);
      emit(SearchError(e));
    }
  }

  /// Fires the analytics event for a tapped result. Navigation is performed
  /// by the caller (which owns the router / BuildContext).
  void selectResult(SearchResultEntity result) {
    _analytics.capture(
      'dashboard',
      'search-result-selected',
      properties: {'type': result.type.name, 'id': result.id},
    );
  }

  /// Cancels any pending query and returns to the idle (dashboard) state.
  void reset() {
    _debounceTimer?.cancel();
    // Invalidate any in-flight request so it can't re-populate results after
    // the user has navigated away / cleared the field.
    _queryGeneration++;
    emit(const SearchIdle());
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    return super.close();
  }
}
