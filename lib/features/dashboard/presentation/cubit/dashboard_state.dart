import '../../../approval/domain/entities/pending_grant.dart';
import '../../domain/entities/onboarding_status.dart';
import '../../domain/entities/recent_entry_entity.dart';

export '../../../approval/domain/entities/pending_grant.dart';
export '../../domain/entities/onboarding_status.dart';
export '../../domain/entities/recent_entry_entity.dart';

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
  const DashboardUnknownAgent({
    required this.grant,
    this.recentEntries = const [],
  });

  /// The pending grant raised by the unregistered agent.
  final PendingGrant grant;

  /// Recently updated entries — silently empty on 403 / network error.
  final List<RecentEntryEntity> recentEntries;
}

/// Normal dashboard with optional recent entries.
final class DashboardLoaded extends DashboardState {
  const DashboardLoaded({this.recentEntries = const []});

  /// Recently updated entries, sorted descending by
  /// [RecentEntryEntity.updatedAt]. Empty when the API returned 403 or
  /// failed — the section is hidden in that case.
  final List<RecentEntryEntity> recentEntries;
}

final class DashboardError extends DashboardState {
  const DashboardError(this.error);

  final Object error;
}
