import 'package:dio/dio.dart';

import '../models/grant_model.dart';

/// Remote data source for the grant-management endpoints.
///
/// Communicates with the .NET Vault module:
/// - `GET    /api/vaults/{vaultId}/grants` — paged list (status/agent filter)
/// - `GET    /api/vaults/{vaultId}/grants/{grantId}` — single grant
/// - `DELETE /api/vaults/{vaultId}/grants/{grantId}` — revoke (opt. reason)
///
/// Returns DTOs — domain mapping happens in the repository layer.
/// DioExceptions surface raw so the repository can classify error
/// semantics into typed `GrantsException`s. Responses never contain
/// crypto material.
class GrantsRemoteDatasource {
  GrantsRemoteDatasource(this._dio);

  final Dio _dio;

  /// `GET /api/vaults/{vaultId}/grants?status=&agentId=&cursor=&pageSize=`
  ///
  /// All filters are optional. Returns one [GrantPage] with the items and
  /// the cursor for the next page (or `null` when exhausted).
  Future<GrantPage> listGrants(
    String vaultId, {
    String? status,
    String? agentId,
    String? cursor,
    int pageSize = 20,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/vaults/$vaultId/grants',
      queryParameters: <String, dynamic>{
        'status': ?status,
        'agentId': ?agentId,
        'cursor': ?cursor,
        'pageSize': pageSize,
      },
    );
    final data = response.data;
    if (data == null) throw _emptyBody(response);

    final raw = (data['items'] as List<dynamic>? ?? const <dynamic>[]);
    final grants = raw
        .map((e) =>
            GrantModel.fromJson(e as Map<String, dynamic>, contextVaultId: vaultId))
        .toList(growable: false);
    return GrantPage(
      grants: grants,
      nextCursor: data['nextCursor'] as String?,
    );
  }

  /// `GET /api/vaults/{vaultId}/grants/{grantId}` → a single grant.
  Future<GrantModel> getGrant(String vaultId, String grantId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/vaults/$vaultId/grants/$grantId',
    );
    final data = response.data;
    if (data == null) throw _emptyBody(response);
    return GrantModel.fromJson(data, contextVaultId: vaultId);
  }

  /// `DELETE /api/vaults/{vaultId}/grants/{grantId}` → 204 (no body).
  ///
  /// [reason] is optional and only sent when non-empty.
  Future<void> revokeGrant(
    String vaultId,
    String grantId, {
    String? reason,
  }) async {
    final trimmed = reason?.trim();
    await _dio.delete<void>(
      '/api/vaults/$vaultId/grants/$grantId',
      data: (trimmed == null || trimmed.isEmpty)
          ? null
          : <String, dynamic>{'reason': trimmed},
    );
  }

  DioException _emptyBody(Response<dynamic> response) => DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Empty response body',
      );
}
