import '../entities/onboarding_status.dart';

/// Domain contract for the dashboard's data needs.
abstract class DashboardRepository {
  /// Fetches the current user's onboarding-step completion flags.
  Future<OnboardingStatus> getOnboardingStatus();
}
