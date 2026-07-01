import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../approval/presentation/cubit/pending_grants_cubit.dart';
import '../../domain/repositories/dashboard_repository.dart';
import 'dashboard_state.dart';

export 'dashboard_state.dart';

/// Drives the home tab: decides between the onboarding checklist, the
/// unknown-agent prompt, and the normal (empty) dashboard.
///
/// Registered as a singleton so the tab keeps its resolved state across
/// shell tab switches; [load] is called on each page mount to refresh.
class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit({
    required this.repository,
    required this.pendingGrantsCubit,
    required this.analytics,
  }) : super(const DashboardInitial());

  final DashboardRepository repository;
  final PendingGrantsCubit pendingGrantsCubit;
  final AnalyticsService analytics;

  /// Persisted flag: the user dismissed the onboarding checklist entirely.
  static const String _kOnboardingSkipped = 'onboarding_skipped';

  /// Persisted flag: the notifications step was enabled or skipped.
  static const String _kNotificationSkipped = 'notification_step_skipped';

  Future<void> load() async {
    emit(const DashboardLoading());
    try {
      // Prefs holds only best-effort UI flags — a plugin/platform-channel
      // hiccup must never blank the whole home, so read defensively and fall
      // back to "not skipped".
      final prefs = await _tryPrefs();

      final recentEntries = await _loadRecentEntriesOrEmpty();

      // Keep the cross-vault pending list current so unknown-agent
      // detection reflects the latest requests (quiet — no skeleton flip).
      await pendingGrantsCubit.refresh();
      final unknownGrant = _firstUnknownAgentGrant();

      final skipped = prefs?.getBool(_kOnboardingSkipped) ?? false;
      if (skipped) {
        emit(
          unknownGrant != null
              ? DashboardUnknownAgent(
                  grant: unknownGrant,
                  recentEntries: recentEntries,
                )
              : DashboardLoaded(recentEntries: recentEntries),
        );
        return;
      }

      final status = await repository.getOnboardingStatus();

      // An unregistered agent request takes precedence over the checklist.
      if (unknownGrant != null) {
        emit(
          DashboardUnknownAgent(
            grant: unknownGrant,
            recentEntries: recentEntries,
          ),
        );
        return;
      }

      if (!status.isSetupComplete) {
        final notificationDone =
            prefs?.getBool(_kNotificationSkipped) ?? false;
        emit(
          DashboardOnboarding(
            status: status,
            notificationStepDone: notificationDone,
          ),
        );
        unawaited(analytics.capture('identity', 'onboarding-viewed'));
        return;
      }

      emit(DashboardLoaded(recentEntries: recentEntries));
    } catch (e, s) {
      AppLogger.e('Dashboard', 'load failed', error: e, stackTrace: s);
      emit(DashboardError(e));
    }
  }

  /// Fetches recent entries, returning `[]` on any error (including 403).
  ///
  /// Failures are logged and suppressed so that a permission gap or a
  /// network hiccup never blanks the whole Home screen.
  Future<List<RecentEntryEntity>> _loadRecentEntriesOrEmpty() async {
    try {
      return await repository.getRecentEntries(5);
    } on DioException catch (e, s) {
      AppLogger.e(
        'Dashboard',
        'recent entries unavailable (${e.response?.statusCode})',
        error: e,
        stackTrace: s,
      );
      return const [];
    } catch (e, s) {
      AppLogger.e('Dashboard', 'recent entries load failed',
          error: e, stackTrace: s);
      return const [];
    }
  }

  /// Best-effort SharedPreferences — the home's skip flags are UI-only, so a
  /// plugin/platform-channel failure returns null (treated as "not skipped")
  /// instead of blanking the whole dashboard behind a generic error.
  Future<SharedPreferences?> _tryPrefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (e, s) {
      AppLogger.e('Dashboard', 'SharedPreferences unavailable', error: e, stackTrace: s);
      return null;
    }
  }

  /// Marks the notifications step as skipped and refreshes the checklist.
  Future<void> skipNotificationStep() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotificationSkipped, true);
    _markNotificationStepDone();
  }

  /// Requests OS notification permission, then marks the step done.
  ///
  /// `permission_handler` is not yet a project dependency, so the actual
  /// OS prompt is stubbed for now — the step is still marked complete so
  /// the checklist advances. Wire the real request in once the package is
  /// added (TODO).
  Future<void> enableNotifications() async {
    unawaited(analytics.capture('identity', 'onboarding-notifications-enabled'));
    // TODO(notifications): request the OS permission via permission_handler
    // (Permission.notification.request()) once the package is added.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotificationSkipped, true);
    _markNotificationStepDone();
  }

  /// Dismisses the onboarding checklist for good.
  Future<void> skipSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingSkipped, true);
    unawaited(analytics.capture('identity', 'onboarding-skipped'));
    emit(const DashboardLoaded());
  }

  void onVaultCtaTapped() =>
      unawaited(analytics.capture('identity', 'onboarding-vault-clicked'));

  void onApiKeyCtaTapped() =>
      unawaited(analytics.capture('identity', 'onboarding-api-key-clicked'));

  void onAgentCtaTapped() =>
      unawaited(analytics.capture('identity', 'onboarding-agent-clicked'));

  /// Fired when the full onboarding is completed; reloads to drop the
  /// checklist in favour of the normal dashboard.
  Future<void> onOnboardingCompleted() async {
    unawaited(analytics.capture('identity', 'onboarding-completed'));
    await load();
  }

  /// Re-emits the current onboarding state with the notifications step
  /// marked done, without a network round-trip.
  void _markNotificationStepDone() {
    final current = state;
    if (current is DashboardOnboarding) {
      emit(
        DashboardOnboarding(
          status: current.status,
          notificationStepDone: true,
        ),
      );
    }
  }

  PendingGrant? _firstUnknownAgentGrant() {
    for (final grant in pendingGrantsCubit.state.grants) {
      if (!grant.isAgentRegistered) return grant;
    }
    return null;
  }
}
