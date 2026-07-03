import '../../domain/entities/onboarding_status.dart';

/// Onboarding projection of the `GET /api/account` response.
///
/// The backend `GetAccountResponse` carries a top-level `isOnboarded`
/// flag and a nested `onboardingSteps` object — camelCase to match the
/// .NET API. Missing flags (or a missing `onboardingSteps` object)
/// default to `false` so a partial response never spuriously marks a
/// step complete.
///
/// [entryCreated] maps from `onboardingSteps.entryCreated` (added in
/// CVT-192). [vaultCreated] from older backend versions is ignored —
/// the default vault is now always auto-created during account setup.
class OnboardingStatusModel {
  const OnboardingStatusModel({
    required this.isOnboarded,
    required this.entryCreated,
    required this.apiKeyCreated,
    required this.agentEnrolled,
  });

  final bool isOnboarded;
  final bool entryCreated;
  final bool apiKeyCreated;
  final bool agentEnrolled;

  factory OnboardingStatusModel.fromJson(Map<String, dynamic> json) {
    final steps = json['onboardingSteps'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return OnboardingStatusModel(
      isOnboarded: json['isOnboarded'] as bool? ?? false,
      entryCreated: steps['entryCreated'] as bool? ?? false,
      apiKeyCreated: steps['apiKeyCreated'] as bool? ?? false,
      agentEnrolled: steps['agentEnrolled'] as bool? ?? false,
    );
  }

  OnboardingStatus toEntity() {
    return OnboardingStatus(
      isOnboarded: isOnboarded,
      entryCreated: entryCreated,
      apiKeyCreated: apiKeyCreated,
      agentEnrolled: agentEnrolled,
    );
  }
}
