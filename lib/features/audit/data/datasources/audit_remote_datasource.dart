import 'package:dio/dio.dart';

import '../models/audit_log_model.dart';

/// One raw page of audit logs from the backend.
class AuditLogModelPage {
  const AuditLogModelPage({required this.items, this.nextCursor});

  final List<AuditLogModel> items;
  final String? nextCursor;
}

/// Remote data source for the audit-log endpoints.
///
/// Communicates with the .NET Audit module:
/// - `GET /api/vaults/{vaultId}/audit-logs` — vault-scoped, newest-first,
///   cursor-paginated. Requires the `AuditView` permission.
///
/// Returns DTOs — domain mapping happens in the repository layer.
/// `DioException`s surface raw so the repository can classify error
/// semantics. Responses never contain crypto material.
class AuditRemoteDatasource {
  AuditRemoteDatasource(this._dio);

  final Dio _dio;

  /// `GET /api/vaults/{vaultId}/audit-logs?cursor=&pageSize=`
  ///
  /// Returns one page of audit entries scoped to [vaultId] plus the cursor
  /// for the next page (or `null` when exhausted). The backend has no
  /// entry-level filter, so entry scoping is applied client-side.
  Future<AuditLogModelPage> listVaultLogs(
    String vaultId, {
    String? cursor,
    int pageSize = 50,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/vaults/$vaultId/audit-logs',
      queryParameters: <String, dynamic>{
        'cursor': ?cursor,
        'pageSize': pageSize,
      },
    );
    final data = response.data;
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Empty response body',
      );
    }

    final raw = (data['items'] as List<dynamic>? ?? const <dynamic>[]);
    final items = raw
        .map((e) => AuditLogModel.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    return AuditLogModelPage(
      items: items,
      nextCursor: data['nextCursor'] as String?,
    );
  }
}
