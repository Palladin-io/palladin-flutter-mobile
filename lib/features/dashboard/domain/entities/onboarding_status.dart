/// Onboarding step completion flags from `GET /api/account/onboarding`.
///
/// The server tracks three setup milestones (vault, API key, agent). The
/// notifications step is purely client-side (an OS permission prompt) and
/// is therefore not represented here.
class OnboardingStatus {
  const OnboardingStatus({
    required this.isOnboarded,
    required this.vaultCreated,
    required this.apiKeyCreated,
    required this.agentEnrolled,
  });

  /// `true` once the server considers account setup complete.
  final bool isOnboarded;
  final bool vaultCreated;
  final bool apiKeyCreated;
  final bool agentEnrolled;

  /// Number of server-tracked steps completed (vault, apiKey, agent = max 3).
  /// The notifications step is client-side only and is counted separately.
  int get serverCompletedCount =>
      (vaultCreated ? 1 : 0) +
      (apiKeyCreated ? 1 : 0) +
      (agentEnrolled ? 1 : 0);
}
