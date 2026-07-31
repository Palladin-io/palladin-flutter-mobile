import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../approval/presentation/cubit/pending_grants_cubit.dart';
import '../../../audit/domain/repositories/audit_repository.dart';
import '../../../audit/presentation/audit_presentation_resolver.dart';
import '../../../notifications/data/services/notification_permission_service.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../../domain/repositories/local_search_repository.dart';
import '../../domain/entities/search_result_entity.dart';
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
    required this.auditRepository,
    required this.auditPresentationResolver,
    required this.pendingGrantsCubit,
    required this.analytics,
    required this.notificationPermissionService,
    LocalSearchRepository? localSearchRepository,
    Stream<String>? recentActivityEntryNameUpdates,
  }) : localSearchRepository =
           localSearchRepository ?? const _EmptyLocalSearchRepository(),
       super(const DashboardInitial()) {
    _entryNameUpdatesSubscription =
        (recentActivityEntryNameUpdates ?? const Stream<String>.empty()).listen(
          _onEntryNameIndexUpdated,
        );
  }

  final DashboardRepository repository;
  final AuditRepository auditRepository;
  final AuditPresentationResolver auditPresentationResolver;
  final PendingGrantsCubit pendingGrantsCubit;
  final AnalyticsService analytics;
  final NotificationPermissionService notificationPermissionService;
  final LocalSearchRepository localSearchRepository;
  late final StreamSubscription<String> _entryNameUpdatesSubscription;
  List<AuditLogEntry> _recentActivitySource = const [];
  AuditPresentationNames _recentActivityNames = const AuditPresentationNames();
  final Set<String> _pendingEntryNameVaults = {};
  var _loadGeneration = 0;
  var _recentActivityGeneration = 0;
  var _refreshingEntryNames = false;

  /// How many recent audit-log rows the Home "Recent Activity" section shows.
  static const int _recentActivityLimit = 6;

  /// Persisted-flag base key: the user dismissed the onboarding checklist.
  /// Scoped per user via [_scopedKey] so a skip made by one account never
  /// hides onboarding for a different account signing in on the same device.
  static const String _kOnboardingSkipped = 'onboarding_skipped';

  /// Persisted-flag base key: the notifications step was enabled or skipped.
  /// Scoped per user via [_scopedKey] (see [_kOnboardingSkipped]).
  static const String _kNotificationSkipped = 'notification_step_skipped';

  /// Builds the per-user SharedPreferences key for a skip flag, e.g.
  /// `onboarding_skipped:{userId}`. Keying by [userId] is the whole fix:
  /// device-wide flags previously leaked one account's dismissal onto every
  /// subsequent account.
  static String _scopedKey(String base, String userId) => '$base:$userId';

  /// Best-effort removal of the legacy device-wide (unscoped) skip flags so no
  /// stale global state lingers once a user has migrated to the per-user keys.
  /// Not required for correctness — the unscoped keys are simply never read
  /// anymore — but this self-heals the store on the next load.
  Future<void> _dropLegacyFlags(SharedPreferences? prefs) async {
    if (prefs == null) return;
    // Fast path — only touch storage on the rare devices that still carry the
    // pre-per-user global keys, instead of removing on every load().
    if (prefs.containsKey(_kOnboardingSkipped)) {
      await prefs.remove(_kOnboardingSkipped);
    }
    if (prefs.containsKey(_kNotificationSkipped)) {
      await prefs.remove(_kNotificationSkipped);
    }
  }

  /// Loads the home tab.
  ///
  /// [canViewAudit] mirrors the caller's `auditView` permission (read from
  /// [AuthBloc] at the page). Only when it is `true` does [load] fetch the
  /// recent org audit-log feed for the "Recent Activity" section — callers
  /// without the permission would get a 403, so we never ask.
  ///
  /// [userId] scopes the persisted onboarding/notification skip flags to the
  /// authenticated user. When it is `null` (no authenticated user resolvable)
  /// we deliberately fall back to "not skipped" — showing onboarding — rather
  /// than reading any device-wide key, so onboarding is never hidden without a
  /// matching per-user flag.
  Future<void> load({bool canViewAudit = false, String? userId}) async {
    final loadGeneration = ++_loadGeneration;
    emit(const DashboardLoading());
    try {
      // Prefs holds only best-effort UI flags — a plugin/platform-channel
      // hiccup must never blank the whole home, so read defensively and fall
      // back to "not skipped".
      final prefs = await _tryPrefs();
      await _dropLegacyFlags(prefs);

      final recentEntries = await _loadRecentEntriesOrEmpty();
      await _loadRecentActivityOrEmpty(canViewAudit, loadGeneration);

      // Keep the cross-vault pending list current so unknown-agent
      // detection reflects the latest requests (quiet — no skeleton flip).
      await pendingGrantsCubit.refresh();
      if (loadGeneration != _loadGeneration || isClosed) return;
      final unknownGrant = _firstUnknownAgentGrant();
      final pendingCount = pendingGrantsCubit.state.grants.length;

      // No userId → no per-user key to read → never treat as skipped.
      final skipped =
          userId != null &&
          (prefs?.getBool(_scopedKey(_kOnboardingSkipped, userId)) ?? false);
      if (skipped) {
        final recentActivity = _currentRecentActivity();
        emit(
          unknownGrant != null
              ? DashboardUnknownAgent(
                  grant: unknownGrant,
                  pendingCount: pendingCount,
                  recentEntries: recentEntries,
                  recentActivity: recentActivity.entries,
                  agentNames: recentActivity.agentNames,
                )
              : DashboardLoaded(
                  recentEntries: recentEntries,
                  recentActivity: recentActivity.entries,
                  agentNames: recentActivity.agentNames,
                ),
        );
        return;
      }

      final status = await repository.getOnboardingStatus();
      if (loadGeneration != _loadGeneration || isClosed) return;

      // An unregistered agent request takes precedence over the checklist.
      if (unknownGrant != null) {
        final recentActivity = _currentRecentActivity();
        emit(
          DashboardUnknownAgent(
            grant: unknownGrant,
            pendingCount: pendingCount,
            recentEntries: recentEntries,
            recentActivity: recentActivity.entries,
            agentNames: recentActivity.agentNames,
          ),
        );
        return;
      }

      if (!status.isSetupComplete) {
        final prefsDone =
            userId != null &&
            (prefs?.getBool(_scopedKey(_kNotificationSkipped, userId)) ??
                false);

        // Check live OS permission — the user may have granted it from outside
        // the app (e.g., via Settings). If already authorized the step is done
        // regardless of what the pref says. Errors in checkStatus() degrade
        // gracefully (returns notDetermined) so load() never throws.
        final permStatus = await notificationPermissionService.checkStatus();
        if (loadGeneration != _loadGeneration || isClosed) return;
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
        unawaited(analytics.capture('dashboard', 'onboarding-viewed'));
        return;
      }

      final recentActivity = _currentRecentActivity();
      emit(
        DashboardLoaded(
          recentEntries: recentEntries,
          recentActivity: recentActivity.entries,
          agentNames: recentActivity.agentNames,
        ),
      );
    } catch (e, s) {
      if (loadGeneration != _loadGeneration || isClosed) return;
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
      return localSearchRepository.recentEntries(limit: 5);
    } catch (_) {
      AppLogger.w('Dashboard', 'Local recent entries unavailable');
      return const [];
    }
  }

  /// Fetches a small page of recent org audit logs for the Home "Recent
  /// Activity" section, returning `[]` on any error.
  ///
  /// Only called when [canViewAudit] is `true` — callers without the
  /// `auditView` permission would get a 403, so we skip the request entirely.
  /// Any failure is logged (never the payload) and suppressed so a permission
  /// gap or network hiccup degrades to an empty section rather than blanking
  /// the whole Home screen.
  Future<void> _loadRecentActivityOrEmpty(
    bool canViewAudit,
    int loadGeneration,
  ) async {
    if (!canViewAudit) {
      _clearRecentActivitySource();
      return;
    }
    try {
      final page = await auditRepository.listOrgLogs(
        pageSize: _recentActivityLimit,
      );
      if (loadGeneration != _loadGeneration || isClosed) return;
      final generation = ++_recentActivityGeneration;
      _recentActivitySource = List.unmodifiable(page.entries);
      _recentActivityNames = const AuditPresentationNames();
      final names = await auditPresentationResolver.resolveNames(page.entries);
      if (loadGeneration != _loadGeneration ||
          generation != _recentActivityGeneration ||
          isClosed) {
        return;
      }
      _recentActivityNames = _recentActivityNames.merge(names);
    } on DioException catch (e, s) {
      if (loadGeneration != _loadGeneration || isClosed) return;
      _clearRecentActivitySource();
      AppLogger.e(
        'Dashboard',
        'recent activity unavailable (${e.response?.statusCode})',
        error: e,
        stackTrace: s,
      );
    } catch (e, s) {
      if (loadGeneration != _loadGeneration || isClosed) return;
      _clearRecentActivitySource();
      AppLogger.e(
        'Dashboard',
        'recent activity load failed',
        error: e,
        stackTrace: s,
      );
    }
  }

  ({List<AuditLogEntry> entries, Map<String, String> agentNames})
  _currentRecentActivity() => (
    entries: auditPresentationResolver.applyNames(
      _recentActivitySource,
      _recentActivityNames,
    ),
    agentNames: _recentActivityNames.agents,
  );

  void _clearRecentActivitySource() {
    _recentActivityGeneration++;
    _recentActivitySource = const [];
    _recentActivityNames = const AuditPresentationNames();
    _pendingEntryNameVaults.clear();
  }

  void _onEntryNameIndexUpdated(String vaultId) {
    if (!_recentActivitySource.any((entry) => entry.vaultId == vaultId)) return;
    _pendingEntryNameVaults.add(vaultId);
    unawaited(_refreshEntryNamesFromReadyIndexes());
  }

  Future<void> _refreshEntryNamesFromReadyIndexes() async {
    if (_refreshingEntryNames) return;
    _refreshingEntryNames = true;
    try {
      while (_pendingEntryNameVaults.isNotEmpty) {
        final vaultIds = Set<String>.from(_pendingEntryNameVaults);
        _pendingEntryNameVaults.clear();
        final generation = _recentActivityGeneration;
        final source = _recentActivitySource;
        var refreshed = const AuditPresentationNames();
        for (final vaultId in vaultIds) {
          final scopedPage = source
              .where((entry) => entry.vaultId == vaultId)
              .toList(growable: false);
          if (scopedPage.isEmpty) continue;
          refreshed = refreshed.merge(
            await auditPresentationResolver.resolveNames(
              scopedPage,
              scopedVaultId: vaultId,
            ),
          );
        }
        if (generation != _recentActivityGeneration || isClosed) continue;
        final refreshedEntryIds = source
            .where((entry) => vaultIds.contains(entry.vaultId))
            .map((entry) => entry.entryId)
            .whereType<String>()
            .toSet();
        final currentEntries = Map<String, String>.from(
          _recentActivityNames.entries,
        )..removeWhere((entryId, _) => refreshedEntryIds.contains(entryId));
        _recentActivityNames = AuditPresentationNames(
          agents: {..._recentActivityNames.agents, ...refreshed.agents},
          vaults: {..._recentActivityNames.vaults, ...refreshed.vaults},
          entries: {...currentEntries, ...refreshed.entries},
          members: {..._recentActivityNames.members, ...refreshed.members},
        );
        _emitRefreshedRecentActivity();
      }
    } finally {
      _refreshingEntryNames = false;
      if (_pendingEntryNameVaults.isNotEmpty && !isClosed) {
        unawaited(_refreshEntryNamesFromReadyIndexes());
      }
    }
  }

  void _emitRefreshedRecentActivity() {
    final entries = auditPresentationResolver.applyNames(
      _recentActivitySource,
      _recentActivityNames,
    );
    final current = state;
    switch (current) {
      case DashboardLoaded():
        emit(
          DashboardLoaded(
            recentEntries: current.recentEntries,
            recentActivity: entries,
            agentNames: {...current.agentNames, ..._recentActivityNames.agents},
          ),
        );
      case DashboardUnknownAgent():
        emit(
          DashboardUnknownAgent(
            grant: current.grant,
            pendingCount: current.pendingCount,
            recentEntries: current.recentEntries,
            recentActivity: entries,
            agentNames: {...current.agentNames, ..._recentActivityNames.agents},
          ),
        );
      default:
        break;
    }
  }

  /// Best-effort SharedPreferences — the home's skip flags are UI-only, so a
  /// plugin/platform-channel failure returns null (treated as "not skipped")
  /// instead of blanking the whole dashboard behind a generic error.
  Future<SharedPreferences?> _tryPrefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (e, s) {
      AppLogger.e(
        'Dashboard',
        'SharedPreferences unavailable',
        error: e,
        stackTrace: s,
      );
      return null;
    }
  }

  /// Marks the notifications step as skipped (for [userId]) and refreshes the
  /// checklist. A `null` [userId] cannot be persisted, so the step is advanced
  /// for this session only — the next [load] shows it again.
  Future<void> skipNotificationStep(String? userId) async {
    final prefs = await _tryPrefs();
    if (userId != null) {
      await prefs?.setBool(_scopedKey(_kNotificationSkipped, userId), true);
    }
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
  Future<void> enableNotifications(String? userId) async {
    final status = await notificationPermissionService.requestPermission();

    if (status == NotificationPermissionStatus.authorized) {
      unawaited(
        analytics.capture('dashboard', 'onboarding-notifications-enabled'),
      );
      final prefs = await _tryPrefs();
      if (userId != null) {
        await prefs?.setBool(_scopedKey(_kNotificationSkipped, userId), true);
      }
      _markNotificationStepDone();
    } else if (status == NotificationPermissionStatus.denied) {
      // iOS: the native prompt will not appear again. Send the user to
      // system settings and update the state so the button label swaps.
      unawaited(
        analytics.capture(
          'dashboard',
          'onboarding-notifications-settings-opened',
        ),
      );
      await notificationPermissionService.openSettings();
      _markNotificationDenied();
    }
    // notDetermined: dialog was dismissed without a decision — do nothing.
  }

  /// Dismisses the onboarding checklist for good (for [userId]). A `null`
  /// [userId] cannot be persisted, so the checklist is dismissed for this
  /// session only — the next [load] shows it again.
  Future<void> skipSetup(String? userId) async {
    final prefs = await _tryPrefs();
    if (userId != null) {
      await prefs?.setBool(_scopedKey(_kOnboardingSkipped, userId), true);
    }
    unawaited(analytics.capture('dashboard', 'onboarding-skipped'));
    emit(const DashboardLoaded());
  }

  void onVaultCtaTapped() =>
      unawaited(analytics.capture('dashboard', 'onboarding-entry-clicked'));

  void onApiKeyCtaTapped() =>
      unawaited(analytics.capture('dashboard', 'onboarding-api-key-clicked'));

  void onAgentCtaTapped() =>
      unawaited(analytics.capture('dashboard', 'onboarding-agent-clicked'));

  /// Drops every decrypted Home projection at the auth lock boundary.
  /// In-flight loads are invalidated so they cannot repopulate the singleton
  /// after the vault has been locked or the session has ended.
  void lock() {
    _loadGeneration++;
    _clearRecentActivitySource();
    emit(const DashboardInitial());
  }

  /// Fired when the full onboarding is completed; reloads to drop the
  /// checklist in favour of the normal dashboard.
  Future<void> onOnboardingCompleted({String? userId}) async {
    unawaited(analytics.capture('dashboard', 'onboarding-completed'));
    await load(userId: userId);
  }

  /// Re-emits the current onboarding state with the notifications step
  /// marked done, without a network round-trip.
  void _markNotificationStepDone() {
    final current = state;
    if (current is DashboardOnboarding) {
      emit(
        DashboardOnboarding(status: current.status, notificationStepDone: true),
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

  @override
  Future<void> close() async {
    await _entryNameUpdatesSubscription.cancel();
    return super.close();
  }
}

final class _EmptyLocalSearchRepository implements LocalSearchRepository {
  const _EmptyLocalSearchRepository();

  @override
  Future<void> prepare(Uint8List memberPrivateKey) async {}

  @override
  List<SearchResultEntity> search(String query, {int limit = 10}) => const [];

  @override
  List<RecentEntryEntity> recentEntries({int limit = 5}) => const [];
}
