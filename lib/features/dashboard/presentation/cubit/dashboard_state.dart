import '../../../approval/domain/entities/pending_grant.dart';
import '../../domain/entities/onboarding_status.dart';

export '../../../approval/domain/entities/pending_grant.dart';
export '../../domain/entities/onboarding_status.dart';

/// States for the dashboard (home tab).
sealed class DashboardState {
  const DashboardState();
}

final class DashboardInitial extends DashboardState {
  const DashboardInitial();
}

final class DashboardLoading extends DashboardState {
  const DashboardLoading();
}

/// Onboarding checklist state — shown to users who have not finished setup
/// and have not dismissed the checklist.
final class DashboardOnboarding extends DashboardState {
  const DashboardOnboarding({
    required this.status,
    required this.notificationStepDone,
  });

  final OnboardingStatus status;

  /// `true` once the user has enabled or skipped the notifications step.
  final bool notificationStepDone;

  /// Completed steps out of 4 (notifications is step 1, client-side).
  int get completedCount =>
      (notificationStepDone ? 1 : 0) + status.serverCompletedCount;
}

/// An unregistered agent is waiting for registration + approval.
final class DashboardUnknownAgent extends DashboardState {
  const DashboardUnknownAgent({required this.grant});

  /// The pending grant raised by the unregistered agent.
  final PendingGrant grant;
}

/// Normal dashboard. For the MVP this is an empty "No activity yet" state.
final class DashboardLoaded extends DashboardState {
  const DashboardLoaded();
}

final class DashboardError extends DashboardState {
  const DashboardError(this.error);

  final Object error;
}
