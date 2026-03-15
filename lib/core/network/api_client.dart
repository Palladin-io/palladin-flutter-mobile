import 'package:dio/dio.dart';

import '../../config/env_config.dart';
import '../storage/secure_token_storage.dart';
import 'auth_interceptor.dart';

/// Creates a pre-configured [Dio] instance pointing at the backend API.
///
/// Includes the [AuthInterceptor] for automatic Bearer-token attachment
/// and 401-refresh handling.
Dio createDio(EnvConfig config, SecureTokenStorage tokenStorage) {
  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  dio.interceptors.add(
    AuthInterceptor(tokenStorage: tokenStorage, dio: dio),
  );

  return dio;
}
