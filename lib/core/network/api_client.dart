import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../../config/env_config.dart';
import '../analytics/analytics_headers_service.dart';
import '../storage/secure_token_storage.dart';
import '../utils/app_logger.dart';
import 'auth_interceptor.dart';
import 'certificate_pinning.dart';

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
    ),
  );

  // TLS SPKI pinning (CVT-213). `validateCertificate` runs only after the
  // system CA chain is trusted and evaluates the leaf; when no pins are
  // configured it is a no-op so local/staging dev is unaffected.
  final pinning = CertificatePinningService(config.certificatePins);
  if (pinning.isEnabled) {
    dio.httpClientAdapter = IOHttpClientAdapter(
      validateCertificate: (cert, host, port) =>
          pinning.validateLeaf(cert, host),
    );
  }

  dio.interceptors.add(_LoggingInterceptor());
  dio.interceptors.add(_AnalyticsHeadersInterceptor());
  dio.interceptors.add(
    AuthInterceptor(tokenStorage: tokenStorage, dio: dio),
  );

  return dio;
}

class _LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    AppLogger.d('HTTP', '-> ${options.method} ${options.path}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    AppLogger.d(
      'HTTP',
      '<- ${response.statusCode} ${response.requestOptions.path}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    AppLogger.e(
      'HTTP',
      '!! ${err.type.name} ${err.requestOptions.path}',
      error: err.message,
    );
    handler.next(err);
  }
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
