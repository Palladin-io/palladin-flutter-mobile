import 'package:dio/dio.dart';

import '../storage/secure_token_storage.dart';

/// Dio interceptor that attaches the Bearer token to outgoing requests
/// and handles 401 responses by attempting a token refresh.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required this.tokenStorage,
    required Dio dio,
  }) : _dio = dio;

  final SecureTokenStorage tokenStorage;
  final Dio _dio;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await tokenStorage.accessToken;
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }

    // Never run the 401→refresh flow for the auth endpoints themselves, and
    // never a second time for an already-retried request — otherwise a 401 on
    // the refresh (dead session) would re-enter this handler and recurse.
    final path = err.requestOptions.path;
    final isAuthPath = path.contains('/api/auth/refresh') ||
        path.contains('/api/auth/login') ||
        path.contains('/api/auth/register');
    final alreadyRetried = err.requestOptions.extra['__retried__'] == true;
    if (isAuthPath || alreadyRetried) {
      // A 401 on refresh/login means the session is dead — drop it so the
      // user is routed back to sign-in rather than looping on a stale token.
      if (path.contains('/api/auth/refresh') ||
          path.contains('/api/auth/login')) {
        await tokenStorage.clearAll();
      }
      handler.next(err);
      return;
    }

    final refresh = await tokenStorage.refreshToken;
    if (refresh == null || refresh.isEmpty) {
      await tokenStorage.clearAll();
      handler.next(err);
      return;
    }

    try {
      final newAccessToken = await _refreshTokens(refresh);

      // Retry the original request once with the new token. The
      // `__retried__` flag guarantees a second 401 short-circuits above
      // instead of triggering another refresh.
      final options = err.requestOptions;
      options.headers['Authorization'] = 'Bearer $newAccessToken';
      options.extra['__retried__'] = true;

      final retryResponse = await _dio.fetch(options);
      handler.resolve(retryResponse);
    } on DioException {
      // Refresh failed — clear tokens and propagate the original error.
      await tokenStorage.clearAll();
      handler.next(err);
    }
  }

  /// Exchanges the refresh token for a fresh access/refresh pair.
  ///
  /// Uses a dedicated, interceptor-free Dio so the refresh request can never
  /// re-enter [AuthInterceptor] and recurse or deadlock the [QueuedInterceptor].
  Future<String> _refreshTokens(String refreshToken) async {
    final refreshDio = Dio(BaseOptions(
      baseUrl: _dio.options.baseUrl,
      connectTimeout: _dio.options.connectTimeout,
      receiveTimeout: _dio.options.receiveTimeout,
    ));

    final response = await refreshDio.post<Map<String, dynamic>>(
      '/api/auth/refresh',
      data: {'refreshToken': refreshToken},
    );

    final data = response.data!;
    final newAccessToken = data['accessToken'] as String;
    final newRefreshToken = data['refreshToken'] as String;

    await tokenStorage.updateTokens(
      accessToken: newAccessToken,
      refreshToken: newRefreshToken,
    );

    return newAccessToken;
  }
}
