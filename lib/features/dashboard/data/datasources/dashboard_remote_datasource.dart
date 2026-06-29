import 'package:dio/dio.dart';

import '../models/onboarding_status_model.dart';

/// Remote data source for the dashboard.
///
/// Reads the user's onboarding-step completion flags from the .NET
/// backend Identity module at `/api/account/onboarding`.
class DashboardRemoteDatasource {
  DashboardRemoteDatasource(this._dio);

  final Dio _dio;

  /// Fetches the current user's onboarding status.
  Future<OnboardingStatusModel> getOnboarding() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/account/onboarding',
    );
    final data = response.data;
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Empty onboarding response body',
      );
    }
    return OnboardingStatusModel.fromJson(data);
  }
}
