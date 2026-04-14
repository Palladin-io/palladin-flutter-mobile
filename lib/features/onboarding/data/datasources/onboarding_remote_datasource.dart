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
    return _dio.post(
      '/api/account/setup',
      data: request.toJson(),
    );
  }
}
