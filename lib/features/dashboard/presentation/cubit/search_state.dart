import '../../domain/entities/search_result_entity.dart';

/// State for the dashboard global-search autocomplete.
///
/// Sealed so the presentation layer can exhaustively switch over every
/// state without a fallback branch.
sealed class SearchState {
  const SearchState();
}

/// No active query (empty field, or fewer than 2 characters typed). The
/// dashboard renders its normal content in this state.
final class SearchIdle extends SearchState {
  const SearchIdle();
}

/// A query is in flight (debounce elapsed, awaiting the backend).
final class SearchLoading extends SearchState {
  const SearchLoading();
}

/// The query returned one or more hits.
final class SearchResults extends SearchState {
  const SearchResults(
    this.results, {
    this.remotePending = false,
    this.remoteFailed = false,
  });

  final List<SearchResultEntity> results;
  final bool remotePending;
  final bool remoteFailed;
}

/// The query completed with no hits.
final class SearchEmpty extends SearchState {
  const SearchEmpty();
}

/// The query failed (network / server error).
final class SearchError extends SearchState {
  const SearchError();
}
