import 'package:dio/dio.dart';

import '../models/auth_result_model.dart';

/// Remote data source for authentication endpoints.
///
/// Communicates with the .NET backend Identity module at `/api/auth/`.
class AuthRemoteDatasource {
  AuthRemoteDatasource(this._dio);

  final Dio _dio;

  /// Exchanges a Google OAuth ID token for backend JWT credentials.
  Future<AuthResultModel> oauthGoogle(String idToken) async {
    final response = await _dio.post(
      '/api/auth/oauth/google',
      data: {
        'token': idToken,
        'platform': 'mobile',
      },
    );
    return _parseAuthResult(response.data);
  }

  /// Exchanges a refresh token for a fresh access/refresh token pair.
  Future<AuthResultModel> refreshToken(String refreshToken) async {
    final response = await _dio.post(
      '/api/auth/refresh',
      data: {'refreshToken': refreshToken},
    );
    return _parseAuthResult(response.data);
  }

  /// Invalidates the given refresh token on the backend.
  Future<void> logout(String refreshToken) async {
    await _dio.post(
      '/api/auth/logout',
      data: {'refreshToken': refreshToken},
    );
  }

  /// Safely parses the response body into [AuthResultModel].
  ///
  /// Throws [FormatException] if the response is not valid JSON or
  /// does not match the expected schema (e.g. HTML error page).
  AuthResultModel _parseAuthResult(dynamic data) {
    try {
      return AuthResultModel.fromJson(data as Map<String, dynamic>);
    } on TypeError catch (_) {
      throw FormatException(
        'Unexpected response format: expected JSON object, '
        'got ${data.runtimeType}',
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Failed to parse auth response: $e');
    }
  }
}
