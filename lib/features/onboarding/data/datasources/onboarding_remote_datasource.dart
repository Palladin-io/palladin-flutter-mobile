import 'package:dio/dio.dart';

import '../models/account_setup_request.dart';

/// Remote data source for onboarding endpoints.
///
/// Communicates with the .NET backend Identity module at `/api/account/`.
class OnboardingRemoteDatasource {
  OnboardingRemoteDatasource(this._dio);

  final Dio _dio;

  /// Submits the user's key material to complete account setup.
  ///
  /// Returns 204 No Content on success, 409 Conflict if the account
  /// has already been set up.
  Future<Response<dynamic>> setupAccount(AccountSetupRequest request) {
    return _dio.post('/api/account/setup', data: request.toJson());
  }

  /// Creates the user's default vault.
  ///
  /// Returns 201 Created on success, 409 Conflict when a default vault
  /// already exists (idempotent — safe to swallow on retry).
  Future<Map<String, dynamic>> issueVaultCreationChallenge() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/vaults/creation-challenges',
    );
    return response.data ??
        (throw const FormatException('Empty Vault creation challenge'));
  }

  Future<Response<dynamic>> createDefaultVault(Map<String, dynamic> request) {
    return _dio.post('/api/account/default-vault', data: request);
  }
}
