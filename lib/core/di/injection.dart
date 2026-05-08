import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

import '../../config/env_config.dart';
import '../../features/auth/data/datasources/auth_remote_datasource.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/onboarding/data/datasources/onboarding_remote_datasource.dart';
import '../../features/onboarding/data/repositories/onboarding_repository_impl.dart';
import '../../features/onboarding/data/services/onboarding_crypto_service.dart';
import '../../features/onboarding/domain/repositories/onboarding_repository.dart';
import '../../features/onboarding/presentation/cubit/onboarding_cubit.dart';
import '../../features/recovery/data/datasources/recovery_remote_datasource.dart';
import '../../features/recovery/data/services/recovery_crypto_service.dart';
import '../../features/recovery/presentation/cubit/recovery_cubit.dart';
import '../../features/unlock/data/datasources/account_remote_datasource.dart';
import '../../features/unlock/data/services/unlock_crypto_service.dart';
import '../../features/unlock/presentation/cubit/unlock_cubit.dart';
import '../../features/vault/data/datasources/vault_remote_datasource.dart';
import '../../features/vault/data/repositories/vault_repository_impl.dart';
import '../../features/vault/data/services/vault_crypto_service.dart';
import '../../features/vault/domain/repositories/vault_repository.dart';
import '../../features/vault/presentation/cubit/create_vault_cubit.dart';
import '../../features/vault/presentation/cubit/vault_detail_cubit.dart';
import '../../features/vault/presentation/cubit/vault_list_cubit.dart';
import '../network/api_client.dart';
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
      googleServerClientId: config.googleServerClientId,
    ),
  );

  // Auth — presentation layer (factory: new instance per provider)
  getIt.registerFactory<AuthBloc>(
    () => AuthBloc(authRepository: getIt<AuthRepository>()),
  );

  // Onboarding — data layer
  getIt.registerLazySingleton<OnboardingRemoteDatasource>(
    () => OnboardingRemoteDatasource(getIt<Dio>()),
  );
  getIt.registerLazySingleton<OnboardingCryptoService>(
    () => OnboardingCryptoService(),
  );
  getIt.registerLazySingleton<OnboardingRepository>(
    () => OnboardingRepositoryImpl(
      remoteDatasource: getIt<OnboardingRemoteDatasource>(),
      cryptoService: getIt<OnboardingCryptoService>(),
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
  getIt.registerLazySingleton<UnlockCryptoService>(
    () => UnlockCryptoService(),
  );

  // Unlock — presentation layer (factory: fresh cubit on each mount
  // so failed-password state doesn't leak between unlock sessions)
  getIt.registerFactory<UnlockCubit>(
    () => UnlockCubit(
      datasource: getIt<AccountRemoteDatasource>(),
      cryptoService: getIt<UnlockCryptoService>(),
      secureStorage: getIt<FlutterSecureStorage>(),
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
  getIt.registerLazySingleton<VaultCryptoService>(
    () => VaultCryptoService(),
  );
  getIt.registerLazySingleton<VaultRemoteDatasource>(
    () => VaultRemoteDatasource(getIt<Dio>()),
  );
  getIt.registerLazySingleton<VaultRepository>(
    () => VaultRepositoryImpl(getIt<VaultRemoteDatasource>()),
  );

  // Vault — presentation layer (factory: fresh cubit per page mount so
  // stale loading / error state never leaks across navigations)
  getIt.registerFactory<VaultListCubit>(
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
}
