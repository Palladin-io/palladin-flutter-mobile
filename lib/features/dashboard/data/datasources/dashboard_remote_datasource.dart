import 'package:dio/dio.dart';

import '../models/onboarding_status_model.dart';

/// Remote data source for the dashboard.
///
/// Reads the user's onboarding status from the .NET backend Identity
/// module at `GET /api/account` — the same endpoint the unlock/recovery
/// flows use. The account payload carries `isOnboarded` plus a nested
/// `onboardingSteps` object; this projection ignores the crypto fields
/// (salt / encrypted private key), which are `null` for a not-onboarded
/// user — precisely the case the onboarding checklist targets — so we
/// never reuse the unlock `AccountResponse` (its `fromJson` requires
/// those fields to be non-null and would throw on the onboarding path).
class DashboardRemoteDatasource {
  DashboardRemoteDatasource(this._dio);

  final Dio _dio;

  /// Fetches the current user's onboarding status from `/api/account`.
  Future<OnboardingStatusModel> getOnboarding() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/account');
    final data = response.data;
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Empty account response body',
      );
    }
    return OnboardingStatusModel.fromJson(data);
  }
}
