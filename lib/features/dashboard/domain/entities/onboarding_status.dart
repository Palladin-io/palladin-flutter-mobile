/// Onboarding step completion flags from `GET /api/account`.
///
/// The server tracks three setup milestones. [entryCreated] replaces the
/// former `vaultCreated` flag — the default "Personal" vault is always
/// auto-created during account setup, so tracking vault creation has no
/// value for the checklist. The meaningful milestone is the first entry.
/// The notifications step is purely client-side (an OS permission prompt)
/// and is therefore not represented here.
class OnboardingStatus {
  const OnboardingStatus({
    required this.isOnboarded,
    required this.entryCreated,
    required this.apiKeyCreated,
    required this.agentEnrolled,
  });

  /// `true` once the server considers account setup complete.
  final bool isOnboarded;

  /// `true` once the user has added at least one password entry.
  final bool entryCreated;

  final bool apiKeyCreated;
  final bool agentEnrolled;

  /// Number of server-tracked steps completed (entry, apiKey, agent = max 3).
  /// The notifications step is client-side only and is counted separately.
  int get serverCompletedCount =>
      (entryCreated ? 1 : 0) +
      (apiKeyCreated ? 1 : 0) +
      (agentEnrolled ? 1 : 0);

  /// `true` once all three server-tracked setup steps are done.
  bool get isSetupComplete => entryCreated && apiKeyCreated && agentEnrolled;
}
