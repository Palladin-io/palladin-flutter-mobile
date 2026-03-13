import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

import '../../config/env_config.dart';
import '../../features/auth/data/datasources/auth_remote_datasource.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
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
    ),
  );

  // Auth — presentation layer (factory: new instance per provider)
  getIt.registerFactory<AuthBloc>(
    () => AuthBloc(authRepository: getIt<AuthRepository>()),
  );
}
