import 'package:dio/dio.dart';

import '../models/onboarding_status_model.dart';
import '../models/search_result_model.dart';

/// Remote data source for the dashboard.
///
/// Reads the user's onboarding status from the .NET backend Identity
/// module at `GET /api/account` — the same endpoint the unlock/recovery
/// flows use. The account payload carries `isOnboarded` plus a nested
/// `onboardingSteps` object; this projection ignores the crypto fields
/// (salt / encrypted private key), which are `null` for a not-onboarded
/// user — precisely the case the onboarding checklist targets — so we
/// keep this projection independent from unlock-specific key-material
/// validation.
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

  /// `POST /api/search` — authorization-scoped Agent/Member catalog search.
  ///
  /// Returns metadata only (type, id, name, optional vaultName + icon); no
  /// encrypted payload is ever returned. The caller is responsible for the
  /// 2-char minimum — the backend also returns an empty list for a query
  /// shorter than 2 characters, so this method never special-cases it.
  Future<List<SearchResultModel>> globalSearch(
    String q,
    int limit, {
    required CancelToken cancelToken,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/search',
      data: <String, dynamic>{'q': q, 'limit': limit},
      cancelToken: cancelToken,
    );
    final data = response.data;
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Empty search response body',
      );
    }
    final raw = (data['results'] as List<dynamic>? ?? const <dynamic>[]);
    if (raw.length > limit) {
      throw const FormatException('Remote search exceeded requested limit');
    }
    return raw
        .map((e) => SearchResultModel.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }
}
