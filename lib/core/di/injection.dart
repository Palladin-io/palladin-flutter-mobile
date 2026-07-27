import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

import '../../config/env_config.dart';
import '../crypto/vault_session_store.dart';
import '../../features/auth/data/datasources/auth_remote_datasource.dart';
import '../../features/auth/data/datasources/password_auth_remote_datasource.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/data/services/hibp_service.dart';
import '../../features/auth/data/services/password_auth_crypto_service.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/auth/presentation/cubit/change_password_cubit.dart';
import '../../features/auth/presentation/cubit/login_cubit.dart';
import '../../features/auth/presentation/cubit/register_cubit.dart';
import '../../features/auth/presentation/cubit/totp_enroll_cubit.dart';
import '../../features/auth/presentation/cubit/verify_email_cubit.dart';
import '../../features/autofill/data/autofill_cache_bridge.dart';
import '../../features/autofill/data/autofill_cache_service.dart';
import '../../features/autofill/data/autofill_mutation_notifier.dart';
import '../../features/autofill/domain/autofill_cache_invalidator.dart';
import '../../features/onboarding/data/datasources/onboarding_remote_datasource.dart';
import '../../features/onboarding/data/repositories/onboarding_repository_impl.dart';
import '../../features/onboarding/data/services/default_vault_provisioner.dart';
import '../../features/onboarding/data/services/onboarding_crypto_service.dart';
import '../../features/onboarding/domain/repositories/onboarding_repository.dart';
import '../../features/onboarding/presentation/cubit/onboarding_cubit.dart';
import '../../features/api_keys/presentation/bloc/api_keys_cubit.dart';
import '../../features/agents/data/datasources/agents_remote_data_source.dart';
import '../../features/agents/data/repositories/agents_repository_impl.dart';
import '../../features/agents/domain/repositories/agents_repository.dart';
import '../../features/agents/presentation/bloc/agents_cubit.dart';
import '../../features/approval/data/datasources/approval_remote_datasource.dart';
import '../../features/approval/data/repositories/approval_repository_impl.dart';
import '../../features/approval/domain/repositories/approval_repository.dart';
import '../../features/approval/presentation/cubit/grant_access_cubit.dart';
import '../../features/approval/presentation/cubit/grant_approval_cubit.dart';
import '../../features/approval/presentation/cubit/pending_grants_cubit.dart';
import '../../features/approval/presentation/cubit/regrant_cubit.dart';
import '../../features/audit/data/datasources/audit_remote_datasource.dart';
import '../../features/audit/data/repositories/audit_repository_impl.dart';
import '../../features/audit/domain/repositories/audit_repository.dart';
import '../../features/audit/presentation/cubit/audit_log_cubit.dart';
import '../../features/audit/presentation/cubit/entry_logs_cubit.dart';
import '../../features/dashboard/data/datasources/dashboard_remote_datasource.dart';
import '../../features/dashboard/data/repositories/dashboard_repository_impl.dart';
import '../../features/dashboard/domain/repositories/dashboard_repository.dart';
import '../../features/dashboard/presentation/cubit/dashboard_cubit.dart';
import '../../features/dashboard/presentation/cubit/search_cubit.dart';
import '../../features/grants/data/datasources/grants_remote_datasource.dart';
import '../../features/grants/data/repositories/grants_repository_impl.dart';
import '../../features/grants/domain/repositories/grants_repository.dart';
import '../../features/grants/presentation/cubit/org_grants_cubit.dart';
import '../../features/notifications/data/datasources/notification_center_remote_datasource.dart';
import '../../features/notifications/data/datasources/push_token_remote_datasource.dart';
import '../../features/notifications/data/repositories/notification_center_repository_impl.dart';
import '../../features/notifications/data/services/notification_permission_service.dart';
import '../../features/notifications/data/services/notification_signalr_service.dart';
import '../../features/notifications/data/services/push_notification_service.dart';
import '../../features/notifications/domain/repositories/notification_center_repository.dart';
import '../../features/notifications/presentation/cubit/notification_center_cubit.dart';
import '../../features/notifications/presentation/cubit/notification_preferences_cubit.dart';
import '../../features/notifications/presentation/cubit/push_navigation_cubit.dart';
import '../analytics/analytics_service.dart';
import '../deep_link/deep_link_service.dart';
import '../../features/recovery/data/datasources/recovery_remote_datasource.dart';
import '../../features/settings/data/datasources/settings_remote_data_source.dart';
import '../../features/settings/data/repositories/settings_repository_impl.dart';
import '../../features/settings/domain/repositories/settings_repository.dart';
import '../../features/settings/presentation/bloc/settings_cubit.dart';
import '../../features/recovery/data/services/recovery_crypto_service.dart';
import '../../features/recovery/presentation/cubit/recovery_cubit.dart';
import '../../features/unlock/data/datasources/account_remote_datasource.dart';
import '../../features/unlock/data/services/unlock_crypto_service.dart';
import '../../features/unlock/presentation/cubit/unlock_cubit.dart';
import '../../features/vault/data/datasources/entry_remote_datasource.dart';
import '../../features/vault/data/datasources/vault_remote_datasource.dart';
import '../../features/vault/data/repositories/entry_repository_impl.dart';
import '../../features/vault/data/repositories/vault_repository_impl.dart';
import '../../features/vault/data/export/export_sharer.dart';
import '../../features/vault/data/services/entry_crypto_service.dart';
import '../../features/vault/data/services/entry_v2_crypto_service.dart';
import '../../features/vault/data/services/totp_service.dart';
import '../../features/vault/data/services/vault_crypto_service.dart';
import '../../features/vault/domain/repositories/entry_repository.dart';
import '../../features/vault/domain/repositories/vault_repository.dart';
import '../../features/vault/presentation/cubit/create_entry_cubit.dart';
import '../../features/vault/presentation/cubit/create_vault_cubit.dart';
import '../../features/vault/presentation/cubit/edit_entry_cubit.dart';
import '../../features/vault/presentation/cubit/entry_list_cubit.dart';
import '../../features/vault/presentation/cubit/export_cubit.dart';
import '../../features/vault/presentation/cubit/import_wizard_cubit.dart';
import '../../features/vault/presentation/cubit/vault_detail_cubit.dart';
import '../../features/vault/presentation/cubit/vault_list_cubit.dart';
import '../network/api_client.dart';
import '../storage/biometric_key_store.dart';
import '../storage/biometric_storage_key_store.dart';
import '../storage/secure_token_storage.dart';

/// Global service locator instance.
final getIt = GetIt.instance;

/// Registers all dependencies into [getIt].
///
/// Must be called once during app startup, before `runApp()`.
void configureDependencies(EnvConfig config) {
  // Config
  getIt.registerSingleton<EnvConfig>(config);

  // Storage
  getIt.registerLazySingleton<FlutterSecureStorage>(
    () => const FlutterSecureStorage(),
  );
  getIt.registerLazySingleton<SecureTokenStorage>(
    () => SecureTokenStorage(getIt<FlutterSecureStorage>()),
  );
  // Enclave-bound, biometric-gated store for the master key (biometric
  // unlock). Never holds the raw MK in a form readable without a fresh
  // biometric authentication — see BiometricStorageKeyStore.
  getIt.registerLazySingleton<BiometricKeyStore>(
    () =>
        BiometricStorageKeyStore(markerStorage: getIt<FlutterSecureStorage>()),
  );
  getIt.registerLazySingleton<AutoFillMutationNotifier>(
    AutoFillMutationNotifier.new,
  );
  getIt.registerLazySingleton<AutoFillCacheBridge>(
    MethodChannelAutoFillCacheBridge.new,
  );

  // Network
  getIt.registerLazySingleton<Dio>(
    () => createDio(config, getIt<SecureTokenStorage>()),
  );

  // Auth — data layer
  getIt.registerLazySingleton<AuthRemoteDatasource>(
    () => AuthRemoteDatasource(getIt<Dio>()),
  );
  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(
      remoteDatasource: getIt<AuthRemoteDatasource>(),
      tokenStorage: getIt<SecureTokenStorage>(),
      secureStorage: getIt<FlutterSecureStorage>(),
      autoFillCacheInvalidator: getIt<AutoFillCacheInvalidator>(),
      googleServerClientId: config.googleServerClientId,
    ),
  );

  // Raw Vault keys are process-memory-only and are wiped on lock/logout.
  getIt.registerLazySingleton<VaultSessionStore>(() => VaultSessionStore());

  // Auth — presentation layer (factory: new instance per provider)
  getIt.registerFactory<AuthBloc>(
    () => AuthBloc(
      authRepository: getIt<AuthRepository>(),
      vaultSessionStore: getIt<VaultSessionStore>(),
    ),
  );

  // Email + master-password auth (CVT-252) — data layer.
  getIt.registerLazySingleton<PasswordAuthCryptoService>(
    () => PasswordAuthCryptoService(),
  );
  getIt.registerLazySingleton<HibpService>(() => HibpService());
  getIt.registerLazySingleton<PasswordAuthRemoteDatasource>(
    () => PasswordAuthRemoteDatasource(getIt<Dio>()),
  );

  // Email + master-password auth — presentation layer. Each screen owns a
  // fresh cubit per mount so failed-attempt state never leaks between
  // sessions, and any in-memory password held for master-key derivation is
  // dropped when the cubit closes.
  getIt.registerFactory<RegisterCubit>(
    () => RegisterCubit(
      datasource: getIt<PasswordAuthRemoteDatasource>(),
      cryptoService: getIt<PasswordAuthCryptoService>(),
      tokenStorage: getIt<SecureTokenStorage>(),
    ),
  );
  getIt.registerFactory<LoginCubit>(
    () => LoginCubit(
      datasource: getIt<PasswordAuthRemoteDatasource>(),
      cryptoService: getIt<PasswordAuthCryptoService>(),
      accountDatasource: getIt<AccountRemoteDatasource>(),
      unlockCryptoService: getIt<UnlockCryptoService>(),
      tokenStorage: getIt<SecureTokenStorage>(),
    ),
  );
  getIt.registerFactory<VerifyEmailCubit>(
    () => VerifyEmailCubit(
      datasource: getIt<PasswordAuthRemoteDatasource>(),
      authRepository: getIt<AuthRepository>(),
      defaultVaultProvisioner: getIt<DefaultVaultProvisioner>(),
    ),
  );
  getIt.registerFactory<ChangePasswordCubit>(
    () => ChangePasswordCubit(
      accountDatasource: getIt<AccountRemoteDatasource>(),
      datasource: getIt<PasswordAuthRemoteDatasource>(),
      cryptoService: getIt<PasswordAuthCryptoService>(),
      keyStore: getIt<BiometricKeyStore>(),
    ),
  );
  getIt.registerFactory<TotpEnrollCubit>(
    () => TotpEnrollCubit(datasource: getIt<PasswordAuthRemoteDatasource>()),
  );

  // Custom-scheme deep links (CVT-261). Singleton — owns the link stream
  // subscription for the whole session; the app-level listener routes
  // resolved links via GoRouter.
  getIt.registerLazySingleton<DeepLinkService>(() => DeepLinkService());

  // Onboarding — data layer
  getIt.registerLazySingleton<OnboardingRemoteDatasource>(
    () => OnboardingRemoteDatasource(getIt<Dio>()),
  );
  getIt.registerLazySingleton<OnboardingCryptoService>(
    () => OnboardingCryptoService(),
  );
  getIt.registerLazySingleton<DefaultVaultProvisioner>(
    () => DefaultVaultProvisioner(
      remoteDatasource: getIt<OnboardingRemoteDatasource>(),
      vaultCryptoService: getIt<VaultCryptoService>(),
      tokenStorage: getIt<SecureTokenStorage>(),
    ),
  );
  getIt.registerLazySingleton<OnboardingRepository>(
    () => OnboardingRepositoryImpl(
      remoteDatasource: getIt<OnboardingRemoteDatasource>(),
      cryptoService: getIt<OnboardingCryptoService>(),
      // VaultCryptoService is needed to generate a wrapped VK for the
      // default vault during onboarding, before the private key is cached
      // in auth state. Registered after the vault section below; get_it
      // resolves lazily so ordering in this file does not matter.
      defaultVaultProvisioner: getIt<DefaultVaultProvisioner>(),
      tokenStorage: getIt<SecureTokenStorage>(),
    ),
  );

  // Onboarding — presentation layer (factory: fresh wizard state
  // per entry, never persisted across sessions)
  getIt.registerFactory<OnboardingCubit>(
    () => OnboardingCubit(repository: getIt<OnboardingRepository>()),
  );

  // Unlock — data layer
  getIt.registerLazySingleton<AccountRemoteDatasource>(
    () => AccountRemoteDatasource(getIt<Dio>()),
  );
  getIt.registerLazySingleton<UnlockCryptoService>(() => UnlockCryptoService());

  // Unlock — presentation layer (factory: fresh cubit on each mount
  // so failed-password state doesn't leak between unlock sessions)
  getIt.registerFactory<UnlockCubit>(
    () => UnlockCubit(
      datasource: getIt<AccountRemoteDatasource>(),
      cryptoService: getIt<UnlockCryptoService>(),
      keyStore: getIt<BiometricKeyStore>(),
      defaultVaultProvisioner: getIt<DefaultVaultProvisioner>(),
    ),
  );

  // Recovery — data layer (reuses the unlock AccountRemoteDatasource
  // for GET /api/account so both flows share one implementation)
  getIt.registerLazySingleton<RecoveryCryptoService>(
    () => RecoveryCryptoService(),
  );
  getIt.registerLazySingleton<RecoveryRemoteDatasource>(
    () => RecoveryRemoteDatasource(
      dio: getIt<Dio>(),
      accountDatasource: getIt<AccountRemoteDatasource>(),
    ),
  );

  // Recovery — presentation layer (factory: fresh cubit per mount so
  // any failed-recovery state is discarded when the user leaves)
  getIt.registerFactory<RecoveryCubit>(
    () => RecoveryCubit(
      datasource: getIt<RecoveryRemoteDatasource>(),
      cryptoService: getIt<RecoveryCryptoService>(),
    ),
  );

  // Vault — data layer
  getIt.registerLazySingleton<VaultCryptoService>(() => VaultCryptoService());
  getIt.registerLazySingleton<VaultRemoteDatasource>(
    () => VaultRemoteDatasource(getIt<Dio>()),
  );
  getIt.registerLazySingleton<VaultRepository>(
    () => VaultRepositoryImpl(
      getIt<VaultRemoteDatasource>(),
      authRepository: getIt<AuthRepository>(),
      accountDatasource: getIt<AccountRemoteDatasource>(),
      cryptoService: getIt<VaultCryptoService>(),
      sessionStore: getIt<VaultSessionStore>(),
      autoFillMutationNotifier: getIt<AutoFillMutationNotifier>(),
    ),
  );

  // VaultListCubit is a singleton so cached vault data survives tab
  // switches. Use BlocProvider.value (never BlocProvider) to avoid
  // automatic close() on widget disposal.
  getIt.registerLazySingleton<VaultListCubit>(
    () => VaultListCubit(repository: getIt<VaultRepository>()),
  );
  getIt.registerFactory<VaultDetailCubit>(
    () => VaultDetailCubit(repository: getIt<VaultRepository>()),
  );
  getIt.registerFactory<CreateVaultCubit>(
    () => CreateVaultCubit(
      repository: getIt<VaultRepository>(),
      cryptoService: getIt<VaultCryptoService>(),
    ),
  );

  // Entry — data layer
  getIt.registerLazySingleton<EntryCryptoService>(() => EntryCryptoService());
  getIt.registerLazySingleton<EntryV2CryptoService>(
    () => EntryV2CryptoService(),
  );
  getIt.registerLazySingleton<TotpService>(() => const TotpService());
  getIt.registerLazySingleton<EntryRemoteDatasource>(
    () => EntryRemoteDatasource(getIt<Dio>()),
  );
  getIt.registerLazySingleton<EntryRepository>(
    () => EntryRepositoryImpl(
      entryDatasource: getIt<EntryRemoteDatasource>(),
      vaultDatasource: getIt<VaultRemoteDatasource>(),
      cryptoService: getIt<EntryCryptoService>(),
      entryV2CryptoService: getIt<EntryV2CryptoService>(),
      sessionStore: getIt<VaultSessionStore>(),
      autoFillMutationNotifier: getIt<AutoFillMutationNotifier>(),
    ),
  );
  getIt.registerLazySingleton<AutoFillCacheService>(
    () => AutoFillCacheService(
      vaultRepository: getIt<VaultRepository>(),
      entryRepository: getIt<EntryRepository>(),
      bridge: getIt<AutoFillCacheBridge>(),
    ),
  );
  getIt.registerLazySingleton<AutoFillCacheInvalidator>(
    () => getIt<AutoFillCacheService>(),
  );

  // Entry — presentation layer (factory: fresh cubit per page mount so
  // stale loading / reveal state never leaks across vaults).
  //
  // `param2` is the optional base64 sealed VK threaded down from the
  // vault detail load — when provided, [revealEntry] skips the extra
  // `GET /api/vaults/{id}` round-trip. Pass `null` and call
  // `cubit.updateWrappedVK(...)` once the vault loads to wire it in.
  getIt.registerFactoryParam<EntryListCubit, String, String?>(
    (vaultId, wrappedVK) => EntryListCubit(
      repository: getIt<EntryRepository>(),
      vaultId: vaultId,
      wrappedVK: wrappedVK,
    ),
  );
  getIt.registerFactory<CreateEntryCubit>(
    () => CreateEntryCubit(repository: getIt<EntryRepository>()),
  );
  getIt.registerFactory<EditEntryCubit>(
    () => EditEntryCubit(repository: getIt<EntryRepository>()),
  );

  // Import wizard (CVT-37) — one cubit per wizard mount, scoped to the
  // target vault. `param1` is the vault id.
  getIt.registerFactoryParam<ImportWizardCubit, String, void>(
    (vaultId, _) => ImportWizardCubit(
      repository: getIt<EntryRepository>(),
      grantsRepository: getIt<GrantsRepository>(),
      vaultId: vaultId,
    ),
  );

  // Export flow (CVT-235) — reveals + serializes + shares a vault.
  getIt.registerLazySingleton<ExportSharer>(
    () => const SharePlusExportSharer(),
  );
  getIt.registerFactory<ExportCubit>(
    () => ExportCubit(
      repository: getIt<EntryRepository>(),
      sharer: getIt<ExportSharer>(),
    ),
  );

  // Settings — data layer (org + API keys)
  getIt.registerLazySingleton<SettingsRemoteDataSource>(
    () => SettingsRemoteDataSource(getIt<Dio>()),
  );
  getIt.registerLazySingleton<SettingsRepository>(
    () => SettingsRepositoryImpl(getIt<SettingsRemoteDataSource>()),
  );

  // Settings — presentation layer (factory: fresh cubit per page mount
  // so stale loading / error state never leaks across visits).
  getIt.registerFactory<SettingsCubit>(
    () => SettingsCubit(repository: getIt<SettingsRepository>()),
  );

  // API keys — presentation layer (factory: fresh cubit per page mount;
  // the list and detail screens each mount their own instance and load
  // independently, so stale state never leaks across visits). Reuses
  // [SettingsRepository] for the shared API-key endpoints.
  getIt.registerFactory<ApiKeysCubit>(
    () => ApiKeysCubit(repository: getIt<SettingsRepository>()),
  );

  // Agents — data layer
  getIt.registerLazySingleton<AgentsRemoteDataSource>(
    () => AgentsRemoteDataSource(getIt<Dio>()),
  );
  getIt.registerLazySingleton<AgentsRepository>(
    () => AgentsRepositoryImpl(getIt<AgentsRemoteDataSource>()),
  );

  // Agents — singleton so the list page and the detail page share one
  // cubit instance. State changes in the detail (icon save, approve,
  // deactivate) are immediately visible in the list without a reload.
  // Lives for the whole app lifecycle (never close()-d) — call
  // AgentsCubit.reset() on logout / org-switch to clear the prior session.
  getIt.registerLazySingleton<AgentsCubit>(
    () => AgentsCubit(repository: getIt<AgentsRepository>()),
  );

  // Notifications (push) — data layer
  getIt.registerLazySingleton<PushTokenRemoteDatasource>(
    () => PushTokenRemoteDatasource(getIt<Dio>()),
  );
  getIt.registerLazySingleton<NotificationCenterRemoteDatasource>(
    () => NotificationCenterRemoteDatasource(getIt<Dio>()),
  );
  getIt.registerLazySingleton<NotificationCenterRepository>(
    () => NotificationCenterRepositoryImpl(
      getIt<NotificationCenterRemoteDatasource>(),
    ),
  );
  // Singleton: the shell reads summary state for the Inbox badge while the
  // Inbox page owns the same cached list.
  getIt.registerLazySingleton<NotificationCenterCubit>(
    () => NotificationCenterCubit(
      repository: getIt<NotificationCenterRepository>(),
    ),
  );
  // Factory: the preferences screen owns transient per-row saving state, so a
  // fresh instance per page mount keeps it from leaking across visits.
  getIt.registerFactory<NotificationPreferencesCubit>(
    () => NotificationPreferencesCubit(
      repository: getIt<NotificationCenterRepository>(),
    ),
  );

  // Push service is a singleton: it owns long-lived FCM stream
  // subscriptions and the device's token lifecycle for the whole app
  // session. Driven by the auth listener — registerForCurrentUser() on
  // login, unregister() on logout.
  getIt.registerLazySingleton<PushNotificationService>(
    () => PushNotificationService(
      datasource: getIt<PushTokenRemoteDatasource>(),
      secureStorage: getIt<FlutterSecureStorage>(),
    ),
  );

  // Stateless permission helper used by DashboardCubit for the onboarding
  // checklist step. Singleton — no state, no streams.
  getIt.registerLazySingleton<NotificationPermissionService>(
    () => NotificationPermissionService(),
  );

  // AnalyticsService is a process-wide singleton (initialized in bootstrap)
  // — register it in the locator so callers depend on the interface rather
  // than the static `instance`, which makes them unit-testable.
  getIt.registerLazySingleton<AnalyticsService>(
    () => AnalyticsService.instance,
  );

  // PushNavigationCubit is a singleton so the app-level deep-link
  // listener stays bound for the whole session; the push service feeds
  // tapped messages into it and the listener performs router.go(...).
  getIt.registerLazySingleton<PushNavigationCubit>(
    () => PushNavigationCubit(analytics: getIt<AnalyticsService>()),
  );

  // In-app real-time channel (SignalR). Singleton: holds the live hub
  // connection for the session, driven by the auth listener in app.dart
  // (connect on login, disconnect on logout).
  getIt.registerLazySingleton<NotificationSignalRService>(
    () => NotificationSignalRService(
      config: getIt<EnvConfig>(),
      tokenStorage: getIt<SecureTokenStorage>(),
    ),
  );

  // Grants — data layer
  getIt.registerLazySingleton<GrantsRemoteDatasource>(
    () => GrantsRemoteDatasource(getIt<Dio>()),
  );
  getIt.registerLazySingleton<GrantsRepository>(
    () => GrantsRepositoryImpl(getIt<GrantsRemoteDatasource>()),
  );

  // OrgGrantsCubit: factory per Approvals "history" segment mount so filter /
  // search state never leaks across visits.
  getIt.registerFactory<OrgGrantsCubit>(
    () => OrgGrantsCubit(repository: getIt<GrantsRepository>()),
  );

  // Audit (CVT-133) — data layer.
  getIt.registerLazySingleton<AuditRemoteDatasource>(
    () => AuditRemoteDatasource(getIt<Dio>()),
  );
  getIt.registerLazySingleton<AuditRepository>(
    () => AuditRepositoryImpl(getIt<AuditRemoteDatasource>()),
  );

  // EntryLogsCubit: factory per entry-detail Logs tab mount, scoped to a
  // vault + entry (param1 = vaultId, param2 = entryId). Resolves agent
  // names from the agents repository to label otherwise id-only rows.
  getIt.registerFactoryParam<EntryLogsCubit, String, String>(
    (vaultId, entryId) => EntryLogsCubit(
      auditRepository: getIt<AuditRepository>(),
      agentsRepository: getIt<AgentsRepository>(),
      vaultId: vaultId,
      entryId: entryId,
    ),
  );

  // AuditLogCubit: factory per Logs surface mount. `param1` is the vault id
  // for the vault-detail Logs tab (CVT-121); pass `null` for the org-wide
  // Logs screen (CVT-66). Scope is inferred from whether a vault id is given.
  getIt.registerFactoryParam<AuditLogCubit, String?, dynamic>(
    (vaultId, _) => AuditLogCubit(
      auditRepository: getIt<AuditRepository>(),
      agentsRepository: getIt<AgentsRepository>(),
      vaultRepository: getIt<VaultRepository>(),
      scope: vaultId == null ? AuditLogScope.org : AuditLogScope.vault,
      vaultId: vaultId,
    ),
  );

  // Approval flow (CVT-58) — data layer.
  getIt.registerLazySingleton<ApprovalRemoteDatasource>(
    () => ApprovalRemoteDatasource(getIt<Dio>()),
  );
  getIt.registerLazySingleton<ApprovalRepository>(
    () => ApprovalRepositoryImpl(
      approvalDatasource: getIt<ApprovalRemoteDatasource>(),
      entryDatasource: getIt<EntryRemoteDatasource>(),
      cryptoService: getIt<EntryV2CryptoService>(),
      sessionStore: getIt<VaultSessionStore>(),
    ),
  );

  // Approval flow — presentation layer.
  // PendingGrantsCubit: singleton so the shell can drive the Approvals nav
  // badge (pending count) and the inbox page shares the same live list. The
  // page provides it via BlocProvider.value (never closes the singleton).
  getIt.registerLazySingleton<PendingGrantsCubit>(
    () => PendingGrantsCubit(repository: getIt<ApprovalRepository>()),
  );
  // GrantApprovalCubit: factory parameterized by the PendingGrant being
  // acted on. param1 = the grant; the owner's private key is passed at
  // call time (never held by DI / the cubit), so the in-memory key
  // material stays scoped to the approve action.
  getIt.registerFactoryParam<GrantApprovalCubit, PendingGrant, void>(
    (grant, _) => GrantApprovalCubit(
      repository: getIt<ApprovalRepository>(),
      grant: grant,
    ),
  );
  // RegrantCubit: factory per "Grant again" sheet; param1 = the re-grant args
  // derived from the terminal grant.
  getIt.registerFactoryParam<RegrantCubit, RegrantArgs, void>(
    (args, _) =>
        RegrantCubit(repository: getIt<ApprovalRepository>(), args: args),
  );

  // GrantAccessCubit: factory per "Add agent / Add grant" sheet (CVT-120/132). Subject is chosen
  // in-sheet, so no construction args.
  getIt.registerFactory<GrantAccessCubit>(
    () => GrantAccessCubit(repository: getIt<ApprovalRepository>()),
  );

  // Dashboard (CVT-114) — data layer.
  getIt.registerLazySingleton<DashboardRemoteDatasource>(
    () => DashboardRemoteDatasource(getIt<Dio>()),
  );
  getIt.registerLazySingleton<DashboardRepository>(
    () => DashboardRepositoryImpl(getIt<DashboardRemoteDatasource>()),
  );

  // Dashboard — presentation. Singleton so the home tab keeps its
  // resolved state across shell tab switches; the page calls load() on
  // each mount to refresh.
  getIt.registerLazySingleton<DashboardCubit>(
    () => DashboardCubit(
      repository: getIt<DashboardRepository>(),
      auditRepository: getIt<AuditRepository>(),
      agentsRepository: getIt<AgentsRepository>(),
      pendingGrantsCubit: getIt<PendingGrantsCubit>(),
      analytics: getIt<AnalyticsService>(),
      notificationPermissionService: getIt<NotificationPermissionService>(),
    ),
  );

  // SearchCubit: factory so each dashboard mount gets a fresh instance
  // (no stale results leak across visits). Reuses the shared
  // DashboardRepository for the /api/search endpoint.
  getIt.registerFactory<SearchCubit>(
    () => SearchCubit(
      repository: getIt<DashboardRepository>(),
      analytics: getIt<AnalyticsService>(),
    ),
  );
}
