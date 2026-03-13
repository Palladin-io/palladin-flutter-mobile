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
    return AuthResultModel.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// Exchanges a refresh token for a fresh access/refresh token pair.
  Future<AuthResultModel> refreshToken(String refreshToken) async {
    final response = await _dio.post(
      '/api/auth/refresh',
      data: {'refreshToken': refreshToken},
    );
    return AuthResultModel.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// Invalidates the given refresh token on the backend.
  Future<void> logout(String refreshToken) async {
    await _dio.post(
      '/api/auth/logout',
      data: {'refreshToken': refreshToken},
    );
  }
}
