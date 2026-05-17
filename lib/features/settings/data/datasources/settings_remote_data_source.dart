import 'package:dio/dio.dart';

import '../models/api_key_model.dart';
import '../models/org_model.dart';

/// Remote data source for the organization and API-key endpoints.
///
/// Communicates with the .NET backend at `/api/org` and `/api/api-keys`.
/// Returns DTOs — domain mapping happens in the repository layer.
/// DioExceptions surface raw so the repository can classify error
/// semantics (404 / 403 / 400 / network) into typed
/// `SettingsException`s.
class SettingsRemoteDataSource {
  SettingsRemoteDataSource(this._dio);

  final Dio _dio;

  /// `GET /api/org` → the caller's organization.
  Future<OrgModel> getOrg() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/org');
    final data = response.data;
    if (data == null) {
      throw _emptyBody(response);
    }
    return OrgModel.fromJson(data);
  }

  /// `PUT /api/org` → 204 No Content.
  Future<void> updateOrgName(String name) async {
    await _dio.put<void>('/api/org', data: {'name': name});
  }

  /// `GET /api/api-keys` → list of API keys for the organization.
  Future<List<ApiKeyModel>> listApiKeys() async {
    final response =
        await _dio.get<Map<String, dynamic>>('/api/api-keys');
    final data = response.data;
    if (data == null) {
      throw _emptyBody(response);
    }
    final raw = (data['items'] as List<dynamic>? ?? const <dynamic>[]);
    return raw
        .map((e) => ApiKeyModel.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// `POST /api/api-keys` → the created key with its one-time plaintext.
  Future<NewApiKeyModel> createApiKey(String name) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/api-keys',
      data: {'name': name},
    );
    final data = response.data;
    if (data == null) {
      throw _emptyBody(response);
    }
    return NewApiKeyModel.fromJson(data);
  }

  /// `DELETE /api/api-keys/{keyId}` → 204 No Content. Idempotent.
  Future<void> revokeApiKey(String keyId) async {
    await _dio.delete<void>('/api/api-keys/$keyId');
  }

  DioException _emptyBody(Response<dynamic> response) => DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Empty response body',
      );
}
