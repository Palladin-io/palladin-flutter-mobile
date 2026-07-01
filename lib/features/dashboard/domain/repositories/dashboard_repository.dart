import '../entities/onboarding_status.dart';
import '../entities/recent_entry_entity.dart';

/// Domain contract for the dashboard's data needs.
abstract class DashboardRepository {
  /// Fetches the current user's onboarding-step completion flags.
  Future<OnboardingStatus> getOnboardingStatus();

  /// Fetches up to [limit] recently updated entries org-wide.
  ///
  /// Callers should handle [DioException] with status 403 by treating the
  /// result as an empty list — membership-gating is expected for some orgs.
  Future<List<RecentEntryEntity>> getRecentEntries(int limit);
}
