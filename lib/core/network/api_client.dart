import 'package:dio/dio.dart';

import '../../config/env_config.dart';
import '../analytics/analytics_headers_service.dart';
import '../storage/secure_token_storage.dart';
import 'auth_interceptor.dart';

/// Creates a pre-configured [Dio] instance pointing at the backend API.
///
/// Includes the [_AnalyticsHeadersInterceptor] for session correlation
/// and [AuthInterceptor] for automatic Bearer-token attachment
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

  dio.interceptors.add(_AnalyticsHeadersInterceptor());
  dio.interceptors.add(
    AuthInterceptor(tokenStorage: tokenStorage, dio: dio),
  );

  return dio;
}

class _AnalyticsHeadersInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final headers = await AnalyticsHeadersService.instance.getHeaders();
    options.headers.addAll(headers);
    handler.next(options);
  }
}
