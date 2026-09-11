import 'core/analytics/analytics_service.dart';
import 'features/privacy/data/consent_activation_store.dart';
import 'features/privacy/data/consent_remote_datasource.dart';
import 'features/privacy/presentation/consent_cubit.dart';
import 'features/privacy/presentation/privacy_runtime.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'l10n/generated/app_localizations.dart';

import 'config/env_config.dart';
import 'core/deep_link/deep_link_service.dart';
import 'core/di/injection.dart';
import 'core/l10n/locale_cubit.dart';
import 'core/identity/organization_member_directory_service.dart';
import 'core/router/app_router.dart';
import 'core/storage/user_preferences.dart';
import 'core/theme/app_colors.dart';
import 'core/utils/app_logger.dart';
import 'core/theme/theme_cubit.dart';
import 'core/widgets/privacy_cover.dart';
import 'features/agents/presentation/bloc/agents_cubit.dart';
import 'features/approval/presentation/cubit/pending_grants_cubit.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/autofill/data/autofill_cache_service.dart';
import 'features/autofill/data/autofill_mutation_notifier.dart';
import 'features/autofill/data/durable_autofill_repair_coordinator.dart';
import 'features/notifications/data/services/notification_signalr_service.dart';
import 'features/notifications/data/services/push_notification_service.dart';
import 'features/notifications/domain/entities/push_message.dart';
import 'features/notifications/presentation/cubit/notification_center_cubit.dart';
import 'features/notifications/presentation/cubit/push_navigation_cubit.dart';
import 'features/dashboard/presentation/cubit/dashboard_cubit.dart';
import 'features/dashboard/presentation/cubit/search_session_controller.dart';
import 'features/vault/data/services/member_index_preparation_service.dart';
import 'features/vault/data/services/member_sync_session_authority_provider.dart';
import 'features/vault/data/services/member_sync_service.dart';
import 'features/vault/data/services/encrypted_presentation_asset_service.dart';
import 'features/vault/data/services/vault_rotation_service.dart';
import 'features/vault/data/export/canonical_export_service.dart';
import 'features/vault/data/export/protected_export_staging.dart';
import 'features/vault/domain/exceptions/vault_exceptions.dart';
import 'features/vault/presentation/cubit/vault_list_cubit.dart';

class PalladinApp extends StatefulWidget {
  const PalladinApp({
    super.key,
    required this.config,
    required this.userPreferences,
    required this.initialThemeMode,
    required this.initialLocale,
  });

  final EnvConfig config;
  final UserPreferences userPreferences;
  final ThemeMode initialThemeMode;
  final Locale initialLocale;

  @override
  State<PalladinApp> createState() => _PalladinAppState();
}

class _PalladinAppState extends State<PalladinApp> with WidgetsBindingObserver {
  // Stable across rebuilds so the push deep-link can navigate via
  // GoRouter regardless of which subtree currently has focus.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  late final ConsentCubit _consents = ConsentCubit(
    ConsentRemoteDataSource(getIt<Dio>()),
    ConsentActivationStore(),
    AnalyticsService.instance,
  );

  late final AuthBloc _authBloc = getIt<AuthBloc>()
    ..add(const AuthCheckRequested());
  late final GoRouter _router = createRouter(
    _authBloc,
    navigatorKey: _navigatorKey,
  );

  final DeepLinkService _deepLink = getIt<DeepLinkService>();
  final PushNavigationCubit _pushNavigationCubit = getIt<PushNavigationCubit>();
  final PushNotificationService _pushService = getIt<PushNotificationService>();
  final AutoFillCacheService _autoFillCache = getIt<AutoFillCacheService>();
  final OrganizationMemberDirectoryService _memberDirectory =
      getIt<OrganizationMemberDirectoryService>();
  final MemberIndexPreparationService _memberIndexPreparation =
      getIt<MemberIndexPreparationService>();
  final MemberSyncService _memberSync = getIt<MemberSyncService>();
  final MemberSyncSessionAuthorityProvider _memberSyncAuthority =
      getIt<MemberSyncSessionAuthorityProvider>();
  final VaultListCubit _vaultList = getIt<VaultListCubit>();
  final DashboardCubit _dashboard = getIt<DashboardCubit>();
  final VaultRotationService _vaultRotation = getIt<VaultRotationService>();
  final CanonicalExportService _exportService = getIt<CanonicalExportService>();
  final ProtectedExportStaging _exportStaging = getIt<ProtectedExportStaging>();
  final EncryptedPresentationAssetService _presentationAssets =
      getIt<EncryptedPresentationAssetService>();
  final SearchSessionController _searchSession =
      getIt<SearchSessionController>();
  late final AutoFillMutationNotifier _autoFillMutationNotifier;
  final Map<String, BigInt> _appliedVaultInvalidationRanks = {};
  final Map<String, VaultSyncInvalidation> _pendingVaultInvalidations = {};
  late final DurableAutoFillRepairCoordinator _durableAutoFillRepair;
  final Set<AutoFillRepairDeny> _mutationAutoFillDenies = {};
  AutoFillRepairDeny? _vaultInvalidationAutoFillDeny;
  Object _autoFillUnlockSessionIdentity = Object();
  bool _vaultInvalidationRepairRunning = false;
  Timer? _vaultInvalidationRepairRetry;
  Timer? _sessionLossAutoFillRetry;
  bool _sessionLossAutoFillCleanupRunning = false;

  // In-app real-time channel (foreground). Works on the simulator too, unlike
  // FCM. Connected while authenticated; FCM/APNs covers the background.
  final NotificationSignalRService _signalR =
      getIt<NotificationSignalRService>();

  /// Backgrounded/inactive — drives the [PrivacyCover] over the app-switcher
  /// snapshot.
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_sweepExportStaging());
    // Forward tapped notifications (background / terminated / cold start)
    // into the navigation cubit, which the BlocListener below consumes.
    _pushService.onMessageTapped = _pushNavigationCubit.onNotificationTapped;
    // Foreground push → live-refresh the relevant list. Tap-routing stays on
    // onMessageTapped above.
    _pushService.onMessageReceived = _onForegroundPush;
    // In-app real-time over SignalR → same refresh handler.
    _signalR.onNotification = _onSignalRNotification;
    _signalR.onVaultSyncInvalidation = _onVaultSyncInvalidation;
    _signalR.onReconnected = _repairCurrentEntries;
    _autoFillMutationNotifier = getIt<AutoFillMutationNotifier>();
    _autoFillMutationNotifier.attachHandler(_onAutoFillMutation);
    _durableAutoFillRepair = DurableAutoFillRepairCoordinator(
      memberIndexes: _memberSync,
      autoFill: _autoFillCache,
      currentSession: () {
        final state = _authBloc.state;
        if (state is! AuthAuthenticated ||
            state.isVaultLocked ||
            state.privateKey == null) {
          return null;
        }
        return AutoFillRepairSession(
          principalId: state.userId,
          identity: _autoFillUnlockSessionIdentity,
          privateKey: state.privateKey!,
        );
      },
      onFailure: (error) => AppLogger.w(
        'AutoFill',
        'Committed-index cache repair failed: ${error.runtimeType}',
      ),
    )..start();
    // Handle a cold start triggered by a notification tap. Guard on `mounted`
    // — if the app is torn down before the future resolves, the cubit may
    // already be closed (Bad state: Cubit is already closed).
    _pushService.initialMessage().then((message) {
      if (!mounted || message == null) return;
      _pushNavigationCubit.onNotificationTapped(message);
    });

    // Custom-scheme deep links (palladin://verify-email?token=…). Resume /
    // warm links route immediately; a cold-start link is applied once the
    // first frame is up so the router has settled its initial redirect.
    _deepLink.listen((route) {
      if (mounted) _router.go(route);
    });
    _deepLink.initialRoute().then((route) {
      if (!mounted || route == null) return;
      _router.go(route);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vaultInvalidationRepairRetry?.cancel();
    _sessionLossAutoFillRetry?.cancel();
    unawaited(_durableAutoFillRepair.dispose());
    _autoFillMutationNotifier.detachHandler();
    _deepLink.dispose();
    _signalR.disconnect();
    _authBloc.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final obscured = state != AppLifecycleState.resumed;
    if (obscured != _obscured) {
      setState(() => _obscured = obscured);
      if (obscured) {
        // Force an early frame so the cover paints before the OS snapshots the
        // app-switcher. No FLAG_SECURE by design — it would also block the
        // user's own screenshots.
        WidgetsBinding.instance.scheduleWarmUpFrame();
        _vaultRotation.pause();
        _searchSession.lock();
      }
    }

    // On returning to the foreground, re-open the real-time channel (idempotent)
    // and quietly refresh live lists so anything that changed while backgrounded
    // (and any events missed while the socket was suspended) shows up.
    if (state == AppLifecycleState.resumed) {
      if (_authBloc.state is AuthAuthenticated) _signalR.connect();
      if (_authBloc.state case final AuthAuthenticated authenticated
          when !authenticated.isVaultLocked &&
              authenticated.privateKey != null) {
        unawaited(
          _prepareLocalSearch(authenticated.privateKey!, ensureFresh: true),
        );
        unawaited(
          _resumeVaultRotations(
            memberId: authenticated.userId,
            privateKey: authenticated.privateKey!,
          ),
        );
      }
      _refreshLiveData();
    }
  }

  /// Quiet refresh of the in-app lists that mirror server state, gated on an
  /// authenticated session so we never hit the API while logged out.
  void _refreshLiveData() {
    if (_authBloc.state is! AuthAuthenticated) return;
    getIt<AgentsCubit>().refresh(ensureFresh: true);
    getIt<PendingGrantsCubit>().refresh(ensureFresh: true);
    getIt<NotificationCenterCubit>().refresh();
  }

  /// A foreground push arrived — refresh the Inbox plus the source list it
  /// affects. Best-effort and auth-gated.
  void _onForegroundPush(PushMessage message) {
    if (_authBloc.state is! AuthAuthenticated) return;
    getIt<NotificationCenterCubit>().refresh();
    switch (message.type) {
      case PushNotificationType.agentPending:
      case PushNotificationType.agentApproved:
        getIt<AgentsCubit>().refresh(ensureFresh: true);
      case PushNotificationType.grantPending:
      case PushNotificationType.grantApproved:
      case PushNotificationType.grantRevoked:
        // A grant lifecycle change also touches agents and the pending-grants
        // queue used by Inbox actions.
        getIt<AgentsCubit>().refresh(ensureFresh: true);
        getIt<PendingGrantsCubit>().refresh(ensureFresh: true);
      case PushNotificationType.credentialStale:
        // Inbox already refreshed above; nothing else to sync.
        break;
      case PushNotificationType.unknown:
        break;
    }
  }

  /// A SignalR (in-app real-time) notification arrived. Unlike FCM, SignalR
  /// carries no OS-level notification, so we surface a visible heads-up banner
  /// ourselves (the web shows a toast for the same events) in addition to
  /// refreshing the affected list.
  void _onSignalRNotification(PushMessage message) {
    _onForegroundPush(message);
    // SignalR carries structural data only. The durable Inbox is refreshed;
    // presentation is resolved there after unlock instead of trusting hub
    // copy or exposing account resources on the lock screen.
  }

  void _onVaultSyncInvalidation(VaultSyncInvalidation invalidation) {
    final state = _authBloc.state;
    if (state is! AuthAuthenticated ||
        state.isVaultLocked ||
        state.privateKey == null) {
      return;
    }
    final rank = _invalidationRank(invalidation);
    final applied = _appliedVaultInvalidationRanks[invalidation.vaultId];
    final pending = _pendingVaultInvalidations[invalidation.vaultId];
    if ((applied != null && rank <= applied) ||
        (pending != null && rank <= _invalidationRank(pending))) {
      return;
    }
    _pendingVaultInvalidations[invalidation.vaultId] = invalidation;
    if (!_vaultInvalidationRepairRunning) {
      unawaited(_drainVaultSyncInvalidations());
    }
  }

  Future<void> _drainVaultSyncInvalidations() async {
    if (_vaultInvalidationRepairRunning) return;
    _vaultInvalidationRepairRunning = true;
    try {
      while (_pendingVaultInvalidations.isNotEmpty) {
        final state = _authBloc.state;
        if (state is! AuthAuthenticated ||
            state.isVaultLocked ||
            state.privateKey == null) {
          _pendingVaultInvalidations.clear();
          return;
        }
        final batch = Map<String, VaultSyncInvalidation>.from(
          _pendingVaultInvalidations,
        );
        _pendingVaultInvalidations.clear();
        try {
          // Commit a durable native deny before any network repair. A remote
          // delete, revoke, policy change or rekey must stop old credentials
          // immediately, not after a potentially slow snapshot/delta fetch.
          final deny = _vaultInvalidationAutoFillDeny ??= _durableAutoFillRepair
              .suspendRepairs();
          await _autoFillCache.clear();
          for (final invalidation in batch.values) {
            if (invalidation.removed) {
              await _memberSync.purgeVault(invalidation.vaultId);
            }
          }
          final preparedVaults = await _memberIndexPreparation.prepare(
            state.privateKey!,
            ensureFresh: true,
          );
          await _durableAutoFillRepair.synchronizePreparedIfAllowed(
            privateKey: state.privateKey!,
            vaultIds: preparedVaults.map((vault) => vault.id),
            releasingDenies: {deny},
          );
          _vaultInvalidationAutoFillDeny = null;
          final currentState = _authBloc.state;
          if (currentState is! AuthAuthenticated ||
              currentState.isVaultLocked ||
              !identical(currentState.privateKey, state.privateKey)) {
            return;
          }
          for (final invalidation in batch.values) {
            final rank = _invalidationRank(invalidation);
            final applied =
                _appliedVaultInvalidationRanks[invalidation.vaultId];
            if (applied == null || rank > applied) {
              _appliedVaultInvalidationRanks[invalidation.vaultId] = rank;
            }
          }
        } catch (error) {
          _memberIndexPreparation.lock();
          for (final invalidation in batch.values) {
            try {
              await _memberSync.purgeVault(invalidation.vaultId);
            } on Object {
              // purgeVault quarantines the Vault in memory before its durable
              // delete, so a storage failure still blocks local reads.
            }
          }
          AppLogger.w(
            'VaultSync',
            'Invalidation repair failed closed: ${error.runtimeType}',
          );
          for (final invalidation in batch.values) {
            final pending = _pendingVaultInvalidations[invalidation.vaultId];
            if (pending == null ||
                _invalidationRank(invalidation) > _invalidationRank(pending)) {
              _pendingVaultInvalidations[invalidation.vaultId] = invalidation;
            }
          }
          _vaultInvalidationRepairRetry ??= Timer(
            const Duration(seconds: 2),
            () {
              _vaultInvalidationRepairRetry = null;
              unawaited(_drainVaultSyncInvalidations());
            },
          );
          return;
        }
      }
    } finally {
      _vaultInvalidationRepairRunning = false;
      if (_pendingVaultInvalidations.isNotEmpty &&
          _vaultInvalidationRepairRetry == null) {
        unawaited(_drainVaultSyncInvalidations());
      }
    }
  }

  BigInt _invalidationRank(VaultSyncInvalidation invalidation) =>
      BigInt.parse(invalidation.mutationVersion) * BigInt.two +
      (invalidation.removed ? BigInt.one : BigInt.zero);

  void _repairCurrentEntries() {
    final state = _authBloc.state;
    if (state is! AuthAuthenticated ||
        state.isVaultLocked ||
        state.privateKey == null) {
      return;
    }
    unawaited(_prepareLocalSearch(state.privateKey!, ensureFresh: true));
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _authBloc),
        BlocProvider.value(value: _consents),
        BlocProvider.value(value: _pushNavigationCubit),
        BlocProvider(
          create: (_) => ThemeCubit(
            widget.userPreferences,
            initial: widget.initialThemeMode,
          ),
        ),
        BlocProvider(
          create: (_) => LocaleCubit(
            widget.userPreferences,
            initial: widget.initialLocale,
          ),
        ),
      ],
      child: MultiBlocListener(
        listeners: [
          // Auth-driven push token lifecycle: register on login, remove
          // on logout. Runs only on state class transitions so a key
          // unlock (which re-emits AuthAuthenticated) doesn't re-register.
          BlocListener<AuthBloc, AuthState>(
            listenWhen: (prev, curr) => prev.runtimeType != curr.runtimeType,
            listener: _onAuthStateChanged,
          ),
          BlocListener<AuthBloc, AuthState>(
            listenWhen: (previous, current) =>
                current is AuthAuthenticated &&
                !current.isVaultLocked &&
                current.privateKey != null &&
                (previous is! AuthAuthenticated || previous.isVaultLocked),
            listener: (_, state) {
              final authenticated = state as AuthAuthenticated;
              _autoFillUnlockSessionIdentity = Object();
              unawaited(
                _startAutoFillSession(privateKey: authenticated.privateKey!),
              );
              unawaited(
                _resumeVaultRotations(
                  memberId: authenticated.userId,
                  privateKey: authenticated.privateKey!,
                ),
              );
            },
          ),
          BlocListener<AuthBloc, AuthState>(
            listenWhen: (previous, current) =>
                previous is AuthAuthenticated &&
                !previous.isVaultLocked &&
                (current is! AuthAuthenticated || current.isVaultLocked),
            listener: (_, _) {
              _memberIndexPreparation.lock();
              _autoFillUnlockSessionIdentity = Object();
              _appliedVaultInvalidationRanks.clear();
              _pendingVaultInvalidations.clear();
              _mutationAutoFillDenies.clear();
              _vaultInvalidationAutoFillDeny = null;
              _durableAutoFillRepair.clearSession();
              _vaultList.lock();
              _dashboard.lock();
              _searchSession.lock();
              getIt<NotificationCenterCubit>().lock();
              _vaultRotation.pause();
              _exportService.cancel();
              _presentationAssets.lock();
              PaintingBinding.instance.imageCache
                ..clear()
                ..clearLiveImages();
              unawaited(_cleanupExportStaging());
            },
          ),
          // Deep-link: navigate when a tapped notification resolves to a
          // route, then clear the cubit so the next tap re-fires.
          BlocListener<PushNavigationCubit, String?>(
            listener: (context, route) {
              if (route == null) return;
              _router.go(route);
              _pushNavigationCubit.consumed();
            },
          ),
        ],
        child: Builder(
          builder: (context) {
            final themeMode = context.watch<ThemeCubit>().state;
            final locale = context.watch<LocaleCubit>().state;

            return MaterialApp.router(
              title: widget.config.appName,
              debugShowCheckedModeBanner: false,
              theme: _buildLightTheme(),
              darkTheme: _buildDarkTheme(),
              themeMode: themeMode,
              locale: locale,
              routerConfig: _router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) {
                return PrivacyRuntime(
                  router: _router,
                  child: Stack(
                    children: [?child, if (_obscured) const PrivacyCover()],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _sweepExportStaging() async {
    try {
      await _exportStaging.sweepStaleExports();
    } catch (_) {
      // Cleanup is best effort; never log paths or platform error payloads.
    }
  }

  Future<void> _prepareLocalSearch(
    Uint8List privateKey, {
    bool ensureFresh = false,
  }) async {
    try {
      final preparedVaults = await _memberIndexPreparation.prepare(
        privateKey,
        ensureFresh: ensureFresh,
      );
      await _durableAutoFillRepair.synchronizePreparedIfAllowed(
        privateKey: privateKey,
        vaultIds: preparedVaults.map((vault) => vault.id),
      );
    } on VaultException catch (error) {
      if (error.kind != VaultErrorKind.networkError) return;
      try {
        final authority = await _memberSyncAuthority.current();
        final cachedVaultIds = await _memberSync.unlockAllCached(
          memberPrivateKey: privateKey,
          authority: authority,
        );
        await _durableAutoFillRepair.synchronizePreparedIfAllowed(
          privateKey: privateKey,
          vaultIds: cachedVaultIds,
        );
      } catch (_) {
        // Cached generations are optional and fail closed per Vault. Never log
        // errors retaining decrypted projection or transport context.
      }
    } catch (_) {
      // Local search is best effort. Never log transport errors because they
      // may retain the raw query or decrypted projection context.
    }
  }

  Future<void> _cleanupExportStaging() async {
    try {
      await _exportStaging.cleanupExports();
    } catch (_) {
      // Cleanup is best effort; never log paths or platform error payloads.
    }
  }

  void _onAuthStateChanged(BuildContext context, AuthState state) {
    if (state is AuthAuthenticated) {
      _sessionLossAutoFillRetry?.cancel();
      _sessionLossAutoFillRetry = null;
      // Fire-and-forget: registration is non-blocking and failure is
      // non-fatal (handled/logged inside the service).
      _pushService.registerForCurrentUser();
      // Open the in-app real-time channel for instant updates.
      _signalR.connect();
    } else if (state is AuthUnauthenticated) {
      _memberDirectory.clear();
      _pushService.unregister();
      _signalR.disconnect();
      getIt<NotificationCenterCubit>().reset();
      unawaited(_clearAutoFillAfterSessionLoss());
    }
  }

  Future<void> _onAutoFillMutation(AutoFillMutationAction action) async {
    switch (action) {
      case AutoFillMutationAction.invalidate:
        final deny = _durableAutoFillRepair.suspendRepairs();
        _mutationAutoFillDenies.add(deny);
        try {
          await _autoFillCache.clear();
        } catch (error) {
          AppLogger.w(
            'AutoFill',
            'Mutation cache invalidation failed: ${error.runtimeType}',
          );
          rethrow;
        }
      case AutoFillMutationAction.rebuild:
        final state = _authBloc.state;
        if (state is! AuthAuthenticated ||
            state.isVaultLocked ||
            state.privateKey == null) {
          return;
        }
        // A mutation invalidates the previous cache before rebuilding. If the
        // rebuild fails, leaving AutoFill empty is safer than serving stale data.
        await _autoFillCache.clear();
        final preparedVaults = await _memberIndexPreparation.prepare(
          state.privateKey!,
          ensureFresh: true,
        );
        await _durableAutoFillRepair.synchronizePreparedIfAllowed(
          privateKey: state.privateKey!,
          vaultIds: preparedVaults.map((vault) => vault.id),
          releasingDenies: Set<AutoFillRepairDeny>.from(
            _mutationAutoFillDenies,
          ),
        );
        _mutationAutoFillDenies.clear();
    }
  }

  Future<void> _startAutoFillSession({required Uint8List privateKey}) async {
    await _autoFillCache.beginSession();
    // Install the complete all-Vault authority before the first native write.
    // A later commit for Vault A must never accidentally drop offline Vault B.
    await _prepareLocalSearch(privateKey);
  }

  Future<void> _resumeVaultRotations({
    required String memberId,
    required Uint8List privateKey,
  }) async {
    try {
      await _vaultRotation.resumeAfterUnlock(
        memberId: memberId,
        memberPrivateKey: privateKey,
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) return;
      AppLogger.w(
        'VaultRotation',
        'Rotation paused after network failure: ${error.type}',
      );
    } catch (error) {
      AppLogger.w(
        'VaultRotation',
        'Rotation requires retry: ${error.runtimeType}',
      );
    }
  }

  Future<void> _clearAutoFillAfterSessionLoss() async {
    if (_sessionLossAutoFillCleanupRunning) return;
    _sessionLossAutoFillCleanupRunning = true;
    var denyConfirmed = false;
    try {
      for (
        var attempt = 1;
        attempt <= _sessionLossAutoFillAttempts &&
            _authBloc.state is! AuthAuthenticated;
        attempt++
      ) {
        try {
          await _autoFillCache.revokeAccess().timeout(
            _sessionLossAutoFillOperationTimeout,
          );
          denyConfirmed = true;
        } catch (error) {
          AppLogger.w(
            'AutoFill',
            'Session-loss access revocation failed '
                '(attempt $attempt/$_sessionLossAutoFillAttempts): '
                '${error.runtimeType}',
          );
        }
        // A new login/unlock owns a newer native generation. Never let this
        // old session-loss continuation clear or revoke that fresh session.
        if (_authBloc.state is AuthAuthenticated) return;
        try {
          await _autoFillCache.clear().timeout(
            _sessionLossAutoFillOperationTimeout,
          );
          denyConfirmed = true;
        } catch (error) {
          AppLogger.w(
            'AutoFill',
            'Session-loss cache invalidation failed '
                '(attempt $attempt/$_sessionLossAutoFillAttempts): '
                '${error.runtimeType}',
          );
        }
        if (_authBloc.state is AuthAuthenticated) return;
        if (denyConfirmed) return;
        await Future<void>.delayed(Duration(seconds: attempt));
      }
    } finally {
      _sessionLossAutoFillCleanupRunning = false;
      if (!denyConfirmed && mounted && _authBloc.state is! AuthAuthenticated) {
        _sessionLossAutoFillRetry ??= Timer(const Duration(seconds: 30), () {
          _sessionLossAutoFillRetry = null;
          unawaited(_clearAutoFillAfterSessionLoss());
        });
      }
    }
  }

  static const _sessionLossAutoFillAttempts = 3;
  static const _sessionLossAutoFillOperationTimeout = Duration(seconds: 5);

  /// Light theme — warm cream background, navy text.
  ThemeData _buildLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
      scaffoldBackgroundColor: AppColors.lightBackground,
      colorScheme: const ColorScheme.light(
        primary: AppColors.brandRed,
        error: AppColors.brandRed,
        surface: AppColors.lightSurface,
        onSurface: AppColors.darkBackground,
        onPrimary: AppColors.onBrandRed,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightSurface,
        foregroundColor: AppColors.darkBackground,
        elevation: 0,
      ),
      datePickerTheme: _datePickerTheme(Brightness.light),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Dark theme — deep navy background, cream text.
  ThemeData _buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      scaffoldBackgroundColor: AppColors.darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.brandRed,
        error: AppColors.brandRed,
        surface: AppColors.darkSurface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: AppColors.onBrandRed,
        elevation: 0,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.brandRed,
      ),
      datePickerTheme: _datePickerTheme(Brightness.dark),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Shared calendar-popup theme for [showDatePicker] (audit From/To filters,
  /// and any future date picker) so the dialog follows the app's light/dark
  /// surface with the brand-red accent — never Material's bare defaults.
  /// Colors come exclusively from [AppColors].
  DatePickerThemeData _datePickerTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final onSurface = isDark ? AppColors.onBrandRed : AppColors.darkBackground;
    final subtle = AppColors.textTertiary;

    Color? selectedBg(Set<WidgetState> states) =>
        states.contains(WidgetState.selected) ? AppColors.brandRed : null;
    Color selectedFg(Set<WidgetState> states, Color unselected) =>
        states.contains(WidgetState.selected)
        ? AppColors.onBrandRed
        : unselected;

    return DatePickerThemeData(
      backgroundColor: surface,
      // Match the tint to the surface so M3 elevation tint can't shift it.
      surfaceTintColor: surface,
      headerBackgroundColor: AppColors.brandRed,
      headerForegroundColor: AppColors.onBrandRed,
      weekdayStyle: TextStyle(color: subtle),
      dayForegroundColor: WidgetStateProperty.resolveWith(
        (states) => selectedFg(states, onSurface),
      ),
      dayBackgroundColor: WidgetStateProperty.resolveWith(selectedBg),
      todayForegroundColor: WidgetStateProperty.resolveWith(
        (states) => selectedFg(states, AppColors.brandRed),
      ),
      todayBackgroundColor: WidgetStateProperty.resolveWith(selectedBg),
      todayBorder: const BorderSide(color: AppColors.brandRed),
      yearForegroundColor: WidgetStateProperty.resolveWith(
        (states) => selectedFg(states, onSurface),
      ),
      yearBackgroundColor: WidgetStateProperty.resolveWith(selectedBg),
      cancelButtonStyle: TextButton.styleFrom(foregroundColor: subtle),
      confirmButtonStyle: TextButton.styleFrom(
        foregroundColor: AppColors.brandRed,
      ),
    );
  }
}
