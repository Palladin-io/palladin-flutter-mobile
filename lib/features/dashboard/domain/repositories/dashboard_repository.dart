import 'package:dio/dio.dart';

import '../entities/onboarding_status.dart';
import '../entities/recent_entry_entity.dart';
import '../entities/search_result_entity.dart';

/// Domain contract for the dashboard's data needs.
abstract class DashboardRepository {
  /// Fetches the current user's onboarding-step completion flags.
  Future<OnboardingStatus> getOnboardingStatus();

  /// Legacy contract retained for source compatibility. Production returns no
  /// backend Entry projections; dashboard recents come from local indexes.
  Future<List<RecentEntryEntity>> getRecentEntries(int limit);

  /// Searches the authorization-scoped Agent/Member catalog.
  ///
  /// [q] must be at least 2 characters — a shorter query yields an empty
  /// list from the backend. Returns metadata-only results (never any
  /// encrypted payload).
  Future<List<SearchResultEntity>> globalSearch(
    String q, {
    int limit = 10,
    required CancelToken cancelToken,
  });
}
