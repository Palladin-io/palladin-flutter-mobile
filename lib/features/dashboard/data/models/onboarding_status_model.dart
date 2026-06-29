import '../../domain/entities/onboarding_status.dart';

/// DTO for `GET /api/account/onboarding`.
///
/// camelCase keys to match the .NET API. Missing flags default to `false`
/// so a partial response never spuriously marks a step complete.
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
    return OnboardingStatusModel(
      isOnboarded: json['isOnboarded'] as bool? ?? false,
      vaultCreated: json['vaultCreated'] as bool? ?? false,
      apiKeyCreated: json['apiKeyCreated'] as bool? ?? false,
      agentEnrolled: json['agentEnrolled'] as bool? ?? false,
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
