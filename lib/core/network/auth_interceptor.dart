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

    // Attempt token refresh on 401
    final refresh = await tokenStorage.refreshToken;
    if (refresh == null || refresh.isEmpty) {
      await tokenStorage.clearAll();
      handler.next(err);
      return;
    }

    try {
      final response = await _dio.post(
        '/api/auth/refresh',
        data: {'refreshToken': refresh},
      );

      final newAccessToken = response.data['accessToken'] as String;
      final newRefreshToken = response.data['refreshToken'] as String;
      final userId = response.data['userId'] as String;
      final isOnboarded = response.data['isOnboarded'] as bool;

      await tokenStorage.saveTokens(
        accessToken: newAccessToken,
        refreshToken: newRefreshToken,
        userId: userId,
        isOnboarded: isOnboarded,
      );

      // Retry the original request with the new token
      final options = err.requestOptions;
      options.headers['Authorization'] = 'Bearer $newAccessToken';

      final retryResponse = await _dio.fetch(options);
      handler.resolve(retryResponse);
    } on DioException {
      // Refresh failed — clear tokens and propagate the original error
      await tokenStorage.clearAll();
      handler.next(err);
    }
  }
}
