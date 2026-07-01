import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../approval/presentation/cubit/pending_grants_cubit.dart';
import '../../../notifications/data/services/notification_permission_service.dart';
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
    required this.notificationPermissionService,
  }) : super(const DashboardInitial());

  final DashboardRepository repository;
  final PendingGrantsCubit pendingGrantsCubit;
  final AnalyticsService analytics;
  final NotificationPermissionService notificationPermissionService;

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
        final prefsDone = prefs?.getBool(_kNotificationSkipped) ?? false;

        // Check live OS permission — the user may have granted it from outside
        // the app (e.g., via Settings). If already authorized the step is done
        // regardless of what the pref says. Errors in checkStatus() degrade
        // gracefully (returns notDetermined) so load() never throws.
        final permStatus =
            await notificationPermissionService.checkStatus();
        final notificationDone =
            prefsDone || permStatus == NotificationPermissionStatus.authorized;
        final permissionDenied =
            !notificationDone &&
            permStatus == NotificationPermissionStatus.denied;

        emit(
          DashboardOnboarding(
            status: status,
            notificationStepDone: notificationDone,
            notificationPermissionDenied: permissionDenied,
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

  /// Requests the OS notification permission.
  ///
  /// - If granted: persists the step as done, fires analytics, advances the
  ///   checklist.
  /// - If denied (iOS cannot re-prompt after the first denial): opens the
  ///   system app-settings page so the user can enable notifications manually.
  ///   The step is NOT marked done — the next [load] call picks up the change
  ///   if the user returns with notifications enabled.
  /// - If dismissed / notDetermined: no-op (user can tap again later).
  Future<void> enableNotifications() async {
    final status = await notificationPermissionService.requestPermission();

    if (status == NotificationPermissionStatus.authorized) {
      unawaited(
        analytics.capture('identity', 'onboarding-notifications-enabled'),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kNotificationSkipped, true);
      _markNotificationStepDone();
    } else if (status == NotificationPermissionStatus.denied) {
      // iOS: the native prompt will not appear again. Send the user to
      // system settings and update the state so the button label swaps.
      unawaited(
        analytics.capture(
          'identity',
          'onboarding-notifications-settings-opened',
        ),
      );
      await notificationPermissionService.openSettings();
      _markNotificationDenied();
    }
    // notDetermined: dialog was dismissed without a decision — do nothing.
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

  /// Re-emits the current onboarding state with [notificationPermissionDenied]
  /// set to `true` so the checklist can swap the button label to "Open
  /// Settings". Does not mark the step as done.
  void _markNotificationDenied() {
    final current = state;
    if (current is DashboardOnboarding) {
      emit(
        DashboardOnboarding(
          status: current.status,
          notificationStepDone: false,
          notificationPermissionDenied: true,
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
