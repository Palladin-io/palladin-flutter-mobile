import '../../../approval/domain/entities/pending_grant.dart';
import '../../../audit/domain/entities/audit_log_entry.dart';
import '../../domain/entities/onboarding_status.dart';
import '../../domain/entities/recent_entry_entity.dart';

export '../../../approval/domain/entities/pending_grant.dart';
export '../../../audit/domain/entities/audit_log_entry.dart';
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
    this.notificationPermissionDenied = false,
  });

  final OnboardingStatus status;

  /// `true` once the user has enabled or skipped the notifications step.
  final bool notificationStepDone;

  /// `true` when the OS permission was explicitly denied and the native
  /// prompt will no longer appear. The checklist swaps the button label to
  /// "Open Settings" so the user can grant it from the OS Settings app.
  final bool notificationPermissionDenied;

  /// Completed steps out of 4 (notifications is step 1, client-side).
  int get completedCount =>
      (notificationStepDone ? 1 : 0) + status.serverCompletedCount;
}

/// An unregistered agent is waiting for registration + approval.
final class DashboardUnknownAgent extends DashboardState {
  const DashboardUnknownAgent({
    required this.grant,
    this.recentEntries = const [],
    this.recentActivity = const [],
  });

  /// The pending grant raised by the unregistered agent.
  final PendingGrant grant;

  /// Recently updated entries — silently empty on 403 / network error.
  final List<RecentEntryEntity> recentEntries;

  /// Recent org audit-log entries, newest-first. Populated only for callers
  /// with the `auditView` permission; silently empty on 403 / network error.
  final List<AuditLogEntry> recentActivity;
}

/// Normal dashboard with optional recent entries.
final class DashboardLoaded extends DashboardState {
  const DashboardLoaded({
    this.recentEntries = const [],
    this.recentActivity = const [],
  });

  /// Recently updated entries, sorted descending by
  /// [RecentEntryEntity.updatedAt]. Empty when the API returned 403 or
  /// failed — the section is hidden in that case.
  final List<RecentEntryEntity> recentEntries;

  /// Recent org audit-log entries, newest-first. Populated only for callers
  /// with the `auditView` permission; silently empty on 403 / network error.
  final List<AuditLogEntry> recentActivity;
}

final class DashboardError extends DashboardState {
  const DashboardError(this.error);

  final Object error;
}
