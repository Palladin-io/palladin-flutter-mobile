import 'core/analytics/analytics_service.dart';
import 'features/privacy/data/consent_remote_datasource.dart';
import 'features/privacy/presentation/consent_cubit.dart';
import 'features/privacy/presentation/privacy_runtime.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'features/shell/presentation/cubit/library_view_cubit.dart';
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
import 'features/autofill/data/autofill_save_controller.dart';
import 'features/autofill/presentation/autofill_save_page.dart';
import 'features/autofill/data/autofill_source_access_service.dart';
import 'features/autofill/data/autofill_source_preparation_service.dart';
import 'features/autofill/data/autofill_source_mutation_repair.dart';
import 'features/autofill/data/autofill_request_session.dart';
import 'features/autofill/data/autofill_request_controller.dart';
import 'features/autofill/presentation/autofill_request_host.dart';
import 'features/autofill/data/autofill_source_invalidator.dart';
import 'features/autofill/data/autofill_auth_lifecycle.dart';
import 'features/autofill/data/generated_password_history_bridge.dart';
import 'features/autofill/data/autofill_mutation_notifier.dart';
import 'features/autofill/data/durable_autofill_repair_coordinator.dart';
import 'features/notifications/data/services/notification_signalr_service.dart';
import 'features/notifications/data/services/push_notification_service.dart';
import 'features/notifications/domain/entities/push_message.dart';
import 'features/notifications/presentation/cubit/notification_center_cubit.dart';
import 'features/notifications/presentation/notification_foreground_repair.dart';
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
import 'features/vault/data/services/entry_sharing/entry_share_ingress.dart';
import 'features/vault/data/services/entry_sharing/entry_share_recipient_authority.dart';
import 'features/vault/presentation/entry_share_account_continuation.dart';
import 'features/vault/data/services/entry_sharing/entry_share_link_service.dart';
import 'features/vault/domain/entities/entry_share.dart';
import 'features/vault/presentation/entry_share_navigation.dart';

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
    AnalyticsService.instance,
  );

  late final AuthBloc _authBloc = getIt<AuthBloc>()
    ..add(const AuthCheckRequested());
  late final GoRouter _router = createRouter(
    _authBloc,
    navigatorKey: _navigatorKey,
    sharingIngress: _sharingIngress,
    sharingAccount: _sharingAccount,
  );
  late final EntryShareIngress? _sharingIngress = _createSharingIngress();
  late final EntryShareAccountContinuation? _sharingAccount =
      _sharingIngress == null
      ? null
      : EntryShareAccountContinuation(
          auth: _authBloc,
          ingress: _sharingIngress,
          ownerReader: getIt<EntryShareRecipientAuthority>().read,
        );
  late final EntryShareNavigation? _sharingNavigation;

  EntryShareIngress? _createSharingIngress() {
    try {
      return EntryShareIngress(links: EntryShareLinkService(widget.config));
    } on EntryShareException {
      return null;
    }
  }

  final DeepLinkService _deepLink = getIt<DeepLinkService>();
  final PushNavigationCubit _pushNavigationCubit = getIt<PushNavigationCubit>();
  final PushNotificationService _pushService = getIt<PushNotificationService>();
  final AutoFillSourceAccessService _autoFillSource =
      getIt<AutoFillSourceAccessService>();
  final AutoFillSourceInvalidator _autoFillInvalidator =
      getIt<AutoFillSourceInvalidator>();
  AutoFillAuthLifecycle? _autoFillAuthLifecycle;
  final bool _supportsAutoFill =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  late final AutoFillSourceMutationRepair _mutationSourceRepair =
      AutoFillSourceMutationRepair(_autoFillSource);
  late final AutoFillSourceMutationRepair _invalidationSourceRepair =
      AutoFillSourceMutationRepair(_autoFillSource);
  final GeneratedPasswordHistoryBridge _generatedPasswordHistory =
      GeneratedPasswordHistoryBridge();
  final AutoFillSaveController _autoFillSave = AutoFillSaveController();
  StreamSubscription<AuthState>? _autoFillSaveAuth;
  Future<String?> _historyActivation = Future<String?>.value(null);
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
  Object _autoFillUnlockSessionIdentity = Object();
  bool _vaultInvalidationRepairRunning = false;
  late final NotificationForegroundRepair _inboxRepair;
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
    _autoFillSave.biometricPrompt = () {
      final context = _navigatorKey.currentContext;
      return context == null
          ? null
          : AppLocalizations.of(context)?.generatedPasswordBiometric;
    };
    _autoFillSave.onDraft = (draft) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final navigator = _navigatorKey.currentState;
        if (!mounted || !draft.valid || navigator == null) {
          _autoFillSave.cancel();
          return;
        }
        unawaited(
          navigator.push<void>(
            MaterialPageRoute(
              builder: (_) =>
                  AutoFillSavePage(controller: _autoFillSave, draft: draft),
            ),
          ),
        );
      });
    };
    _autoFillSaveAuth = _authBloc.stream.listen(_synchronizeAutoFillSave);
    _synchronizeAutoFillSave(_authBloc.state);
    _inboxRepair =
        NotificationForegroundRepair(
          auth: _authBloc,
          vaults: _vaultList,
          inbox: getIt<NotificationCenterCubit>(),
          readAuthority: _memberSyncAuthority.current,
        )..start(
          foreground:
              WidgetsBinding.instance.lifecycleState == null ||
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed,
        );
    final ingress = _sharingIngress;
    _sharingNavigation = ingress == null
        ? null
        : EntryShareNavigation(ingress, _router);
    _sharingNavigation?.start();
    if (ingress != null) unawaited(ingress.start());
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
      autoFill: getIt<AutoFillSourcePreparationService>(),
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
        'Committed-index source activation failed: ${error.runtimeType}',
      ),
    );
    if (_supportsAutoFill) _durableAutoFillRepair.start();
    if (_supportsAutoFill) {
      _autoFillAuthLifecycle = AutoFillAuthLifecycle(
        initialState: _authBloc.state,
        states: _authBloc.stream,
        source: _autoFillSource,
        onTransition: () {
          _autoFillUnlockSessionIdentity = Object();
          _mutationSourceRepair.clearSession();
          _invalidationSourceRepair.clearSession();
          _autoFillMutationNotifier.resetSession();
          _durableAutoFillRepair.clearSession();
          _pendingVaultInvalidations.clear();
          _appliedVaultInvalidationRanks.clear();
        },
        onFailure: (error) => AppLogger.w(
          'AutoFill',
          'Source session transition denied: ${error.runtimeType}',
        ),
      );
    }
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
    unawaited(_autoFillAuthLifecycle?.dispose());
    if (_supportsAutoFill) {
      unawaited(_autoFillSource.endSession().catchError((Object _) {}));
    }
    unawaited(_autoFillSaveAuth?.cancel());
    _autoFillSave.dispose();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_inboxRepair.dispose());
    _vaultInvalidationRepairRetry?.cancel();
    _sessionLossAutoFillRetry?.cancel();
    unawaited(_durableAutoFillRepair.dispose());
    _autoFillMutationNotifier.detachHandler();
    _deepLink.dispose();
    _sharingNavigation?.dispose();
    _sharingAccount?.dispose();
    _sharingIngress?.dispose();
    _signalR.disconnect();
    _authBloc.close();
    super.dispose();
  }

  void _synchronizeAutoFillSave(AuthState state) {
    unawaited(
      _autoFillSave.synchronize(
        state is AuthAuthenticated ? state.userId : null,
        unlocked:
            state is AuthAuthenticated &&
            !state.isVaultLocked &&
            state.privateKey != null,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_autoFillSave.resume());
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _autoFillSave.background();
    }
    _inboxRepair.setForeground(state == AppLifecycleState.resumed);
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
              authenticated.privateKey != null &&
              (!_supportsAutoFill ||
                  !getIt<AutoFillRequestController>().isAuthenticating)) {
        void repair() {
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

        final lifecycle = _autoFillAuthLifecycle;
        if (lifecycle == null) {
          repair();
        } else {
          lifecycle.runForegroundRepair(repair);
        }
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
    if (state is! AuthAuthenticated) return;
    if (state.isVaultLocked || state.privateKey == null) {
      if (_supportsAutoFill) unawaited(_denyLockedSourceInvalidation());
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

  Future<void> _denyLockedSourceInvalidation() async {
    try {
      await _invalidationSourceRepair.invalidateCommitted();
    } catch (_) {
      // Failure retains the source owner's deny; never reactivate old data.
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
        final identity = _autoFillUnlockSessionIdentity;
        final validateSource = _autoFillSource.captureSessionGuard();
        bool isCurrent() {
          try {
            validateSource();
            _validateUnlockedKey(state.privateKey!, identity);
            return true;
          } on StateError {
            return false;
          }
        }

        final batch = Map<String, VaultSyncInvalidation>.from(
          _pendingVaultInvalidations,
        );
        _pendingVaultInvalidations.clear();
        try {
          // Commit a durable native deny before any network repair. A remote
          // delete, revoke, policy change or rekey must stop old credentials
          // immediately, not after a potentially slow snapshot/delta fetch.
          if (_supportsAutoFill) {
            await _invalidationSourceRepair.invalidateCommitted();
          }
          if (!isCurrent()) return;
          for (final invalidation in batch.values) {
            if (!isCurrent()) return;
            if (invalidation.removed) {
              await _memberSync.purgeVault(invalidation.vaultId);
            }
          }
          await _prepareSource(state.privateKey!, ensureFresh: true);
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
          if (!isCurrent()) return;
          _memberIndexPreparation.lock();
          for (final invalidation in batch.values) {
            if (!isCurrent()) return;
            try {
              await _memberSync.purgeVault(invalidation.vaultId);
            } on Object {
              // purgeVault quarantines the Vault in memory before its durable
              // delete, so a storage failure still blocks local reads.
            }
          }
          if (!isCurrent()) return;
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
          lazy: false,
          create: (_) => LibraryViewCubit(widget.userPreferences),
        ),
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
          BlocListener<AuthBloc, AuthState>(
            listenWhen: SearchSessionController.replacesUnlockedSession,
            listener: (_, state) => _searchSession.replaceUnlockedSession(
              state as AuthAuthenticated,
              invalidatePreparation: () {
                _vaultList.lock();
                _memberIndexPreparation.lock();
              },
            ),
          ),
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
                (previous is! AuthAuthenticated ||
                    previous.isVaultLocked ||
                    SearchSessionController.replacesUnlockedSession(
                      previous,
                      current,
                    )),
            listener: (_, state) {
              final authenticated = state as AuthAuthenticated;
              _autoFillUnlockSessionIdentity = Object();
              _historyActivation = _generatedPasswordHistory
                  .activate(authenticated.userId)
                  .then<String?>((token) => token)
                  .catchError((Object _) => null);
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
                  child: AutoFillRequestHost(
                    navigatorKey: _navigatorKey,
                    prepare: _prepareAutoFillRequest,
                    child: Stack(
                      children: [?child, if (_obscured) const PrivacyCover()],
                    ),
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

  void _validateUnlockedKey(Uint8List privateKey, Object identity) {
    final state = _authBloc.state;
    if (!mounted ||
        !identical(identity, _autoFillUnlockSessionIdentity) ||
        state is! AuthAuthenticated ||
        state.isVaultLocked ||
        !identical(state.privateKey, privateKey)) {
      throw StateError('Unlocked session changed');
    }
  }

  Future<List<String>> _prepareSource(
    Uint8List privateKey, {
    bool ensureFresh = false,
  }) async {
    final identity = _autoFillUnlockSessionIdentity;
    _validateUnlockedKey(privateKey, identity);
    if (_supportsAutoFill) await _autoFillSource.ensureSession();
    _validateUnlockedKey(privateKey, identity);
    List<String> vaultIds;
    try {
      final prepared = !_supportsAutoFill
          ? await _memberIndexPreparation.prepare(
              privateKey,
              ensureFresh: ensureFresh,
            )
          : await _mutationSourceRepair.prepare(
              () => _invalidationSourceRepair.prepare(
                () => _memberIndexPreparation.prepare(
                  privateKey,
                  ensureFresh:
                      ensureFresh ||
                      _mutationSourceRepair.needsReconciliation ||
                      _invalidationSourceRepair.needsReconciliation,
                ),
                validateCurrent: () =>
                    _validateUnlockedKey(privateKey, identity),
              ),
              validateCurrent: () => _validateUnlockedKey(privateKey, identity),
            );
      vaultIds = prepared.map((vault) => vault.id).toList();
    } on VaultException catch (error) {
      if (error.kind != VaultErrorKind.networkError) rethrow;
      _validateUnlockedKey(privateKey, identity);
      final authority = await _memberSyncAuthority.current();
      _validateUnlockedKey(privateKey, identity);
      // Offline recovery never completes an outstanding mutation owner.
      vaultIds = await _memberSync.unlockAllCached(
        memberPrivateKey: privateKey,
        authority: authority,
      );
    }
    _validateUnlockedKey(privateKey, identity);
    final published =
        !_supportsAutoFill ||
        await _durableAutoFillRepair.synchronizePreparedIfAllowed(
          privateKey: privateKey,
          vaultIds: vaultIds,
        );
    _validateUnlockedKey(privateKey, identity);
    if (!published) throw StateError('Source activation unavailable');
    return vaultIds;
  }

  Future<AutoFillRequestSession> _prepareAutoFillRequest() async {
    final state = _authBloc.state;
    if (state is! AuthAuthenticated ||
        state.isVaultLocked ||
        state.privateKey == null) {
      throw StateError('AutoFill requires an unlocked session');
    }
    final identity = _autoFillUnlockSessionIdentity;
    final key = state.privateKey!;
    final vaultIds = await _prepareSource(key);
    _validateUnlockedKey(key, identity);
    return AutoFillRequestSession(
      privateKey: key,
      vaultIds: vaultIds,
      validateCurrent: () => _validateUnlockedKey(key, identity),
    );
  }

  Future<void> _prepareLocalSearch(
    Uint8List privateKey, {
    bool ensureFresh = false,
  }) async {
    try {
      await _prepareSource(privateKey, ensureFresh: ensureFresh);
    } catch (_) {
      // Search is best effort. Native access remains denied on failed repair;
      // errors may retain decrypted projections or transport context.
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
    } else if (state is AuthUnauthenticated || state is AuthError) {
      _memberDirectory.clear();
      _pushService.unregister();
      _signalR.disconnect();
      getIt<NotificationCenterCubit>().reset();
      if (_supportsAutoFill) unawaited(_clearAutoFillAfterSessionLoss());
    }
  }

  Future<void> _onAutoFillMutation(AutoFillMutationAction action) async {
    if (!_supportsAutoFill) return;
    switch (action) {
      case AutoFillMutationAction.invalidate:
        await _mutationSourceRepair.invalidate();
      case AutoFillMutationAction.rebuild:
        await _mutationSourceRepair.markCommitted();
        final state = _authBloc.state;
        if (state is! AuthAuthenticated ||
            state.isVaultLocked ||
            state.privateKey == null) {
          return;
        }
        await _prepareSource(state.privateKey!, ensureFresh: true);
    }
  }

  Future<void> _startAutoFillSession({required Uint8List privateKey}) async {
    // Ordinary Vault unlock reuses the account's protected source session.
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
    final historyActivation = _historyActivation;
    var denyConfirmed = false;
    try {
      for (
        var attempt = 1;
        attempt <= _sessionLossAutoFillAttempts &&
            _authBloc.state is! AuthAuthenticated;
        attempt++
      ) {
        var historyRevoked = false;
        try {
          final token = await historyActivation;
          if (_authBloc.state is AuthAuthenticated) return;
          if (token != null) {
            await _generatedPasswordHistory
                .revoke(token)
                .timeout(_sessionLossAutoFillOperationTimeout);
          } else {
            await _generatedPasswordHistory.revokeAllSessions().timeout(
              _sessionLossAutoFillOperationTimeout,
            );
          }
          historyRevoked = true;
        } catch (error) {
          AppLogger.w(
            'AutoFill',
            'Generated-password session revocation failed: ${error.runtimeType}',
          );
        }
        if (_authBloc.state is AuthAuthenticated) return;
        try {
          // The lifecycle barrier owns source denial. This only removes the
          // retired derivative, which no current path writes or authorizes.
          await _autoFillInvalidator.retireLegacy().timeout(
            _sessionLossAutoFillOperationTimeout,
          );
          denyConfirmed = historyRevoked;
        } catch (error) {
          AppLogger.w(
            'AutoFill',
            'Legacy retirement failed (attempt $attempt): ${error.runtimeType}',
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
          if (_supportsAutoFill) unawaited(_clearAutoFillAfterSessionLoss());
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
