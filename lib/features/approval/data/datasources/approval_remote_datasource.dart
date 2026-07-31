import 'package:dio/dio.dart';

import '../models/pending_grant_model.dart';

/// Remote data source for the approval flow.
///
/// Endpoints (.NET Vault + Dashboard modules):
/// - `GET /api/dashboard/pending-grants` — cross-vault pending requests.
/// - `PUT /api/vaults/{vaultId}/grants/{grantId}/approve` — submit the
///   on-device-produced envelope + exactly one of expiry/limit.
/// - `PUT /api/vaults/{vaultId}/grants/{grantId}/deny` — deny with reason.
///
/// The approve body never carries plaintext — only the sealed envelope.
class ApprovalRemoteDatasource {
  ApprovalRemoteDatasource(this._dio);

  final Dio _dio;

  /// `GET /api/dashboard/pending-grants` → all pending grant requests for
  /// the user across every vault they manage.
  Future<PendingGrantPage> listPendingGrants({String? cursor}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/dashboard/pending-grants',
      queryParameters: {'pageSize': 100, 'cursor': ?cursor},
    );
    final data = response.data;
    if (data == null) throw _emptyBody(response);
    final raw = (data['items'] as List<dynamic>? ?? const <dynamic>[]);
    return PendingGrantPage(
      items: raw
          .map((e) => PendingGrantModel.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      nextCursor: data['nextCursor'] as String?,
    );
  }

  Future<PendingGrantModel> getGrant(String vaultId, String grantId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/vaults/$vaultId/grants/$grantId',
    );
    final data = response.data;
    if (data == null) throw _emptyBody(response);
    return PendingGrantModel.fromJson(data);
  }

  /// `POST /api/vaults/{vaultId}/grants` — proactively (re-)grant access.
  ///
  /// [type] is `"granular"` or `"full"`; [entryId] is set only for granular.
  /// [entries] carries one on-device-produced envelope per covered entry
  /// (exactly one for granular, every vault entry for full). At most one of
  /// [expiresAt] / [queryLimit] is sent (neither = lifetime). Returns the new
  /// grant id.
  Future<String> createGrant({
    required String vaultId,
    required String grantId,
    required String agentId,
    required String type,
    String? entryId,
    required List<({String entryId, Map<String, dynamic> envelope})> entries,
    String? expiresAt,
    int? queryLimit,
    String? methods,
  }) async {
    final body = <String, dynamic>{
      'grantId': grantId,
      'agentId': agentId,
      'type': type,
      'entryId': ?entryId,
      'grantEntries': [for (final e in entries) e.envelope],
      'expiresAt': ?expiresAt,
      'queryLimit': ?queryLimit,
      'methods': ?methods,
    };
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/vaults/$vaultId/grants',
      data: body,
    );
    return response.data?['id'] as String? ?? '';
  }

  /// `PUT /api/vaults/{vaultId}/grants/{grantId}/approve`.
  ///
  /// Sends the [envelope] for [entryId] plus **exactly one** of
  /// [expiresAt] (ISO-8601 UTC) / [queryLimit] — the caller is
  /// responsible for enforcing the XOR; this method only serializes
  /// whichever is non-null.
  Future<void> approveGrant({
    required String vaultId,
    required String grantId,
    required Map<String, dynamic> grantEntry,
    String? expiresAt,
    int? queryLimit,
    String? methods,
  }) async {
    final body = <String, dynamic>{
      'grantEntry': grantEntry,
      'expiresAt': ?expiresAt,
      'queryLimit': ?queryLimit,
      'methods': ?methods,
    };
    await _dio.put<void>(
      '/api/vaults/$vaultId/grants/$grantId/approve',
      data: body,
    );
  }

  /// `PUT /api/vaults/{vaultId}/grants/{grantId}/deny`.
  Future<void> denyGrant({
    required String vaultId,
    required String grantId,
  }) async {
    await _dio.put<void>('/api/vaults/$vaultId/grants/$grantId/deny');
  }

  DioException _emptyBody(Response<dynamic> response) => DioException(
    requestOptions: response.requestOptions,
    response: response,
    type: DioExceptionType.badResponse,
    error: 'Empty response body',
  );
}

final class PendingGrantPage {
  const PendingGrantPage({required this.items, this.nextCursor});
  final List<PendingGrantModel> items;
  final String? nextCursor;
}
