import '../../domain/entities/onboarding_status.dart';

/// Onboarding projection of the `GET /api/account` response.
///
/// The backend `GetAccountResponse` carries a top-level `isOnboarded`
/// flag and a nested `onboardingSteps` object
/// (`{ vaultCreated, apiKeyCreated, agentEnrolled }`) — camelCase to
/// match the .NET API. Missing flags (or a missing `onboardingSteps`
/// object) default to `false` so a partial response never spuriously
/// marks a step complete.
class OnboardingStatusModel {
  const OnboardingStatusModel({
    required this.isOnboarded,
    required this.vaultCreated,
    required this.apiKeyCreated,
    required this.agentEnrolled,
  });

  final bool isOnboarded;
  final bool vaultCreated;
  final bool apiKeyCreated;
  final bool agentEnrolled;

  factory OnboardingStatusModel.fromJson(Map<String, dynamic> json) {
    final steps = json['onboardingSteps'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return OnboardingStatusModel(
      isOnboarded: json['isOnboarded'] as bool? ?? false,
      vaultCreated: steps['vaultCreated'] as bool? ?? false,
      apiKeyCreated: steps['apiKeyCreated'] as bool? ?? false,
      agentEnrolled: steps['agentEnrolled'] as bool? ?? false,
    );
  }

  OnboardingStatus toEntity() {
    return OnboardingStatus(
      isOnboarded: isOnboarded,
      vaultCreated: vaultCreated,
      apiKeyCreated: apiKeyCreated,
      agentEnrolled: agentEnrolled,
    );
  }
}
