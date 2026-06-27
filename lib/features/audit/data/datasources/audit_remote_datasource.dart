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
/// - `GET /api/audit-logs` — org-scoped (all vaults), newest-first,
///   cursor-paginated.
///
/// Both endpoints accept optional server-side filters (`actions`/`eventType`,
/// `agentId`, `entryId`, `vaultId`, `from`, `to`). Returns DTOs — domain
/// mapping happens in the repository layer. `DioException`s surface raw so the
/// repository can classify error semantics. Responses never contain crypto
/// material.
class AuditRemoteDatasource {
  AuditRemoteDatasource(this._dio);

  final Dio _dio;

  /// `GET /api/vaults/{vaultId}/audit-logs`
  ///
  /// Returns one page of audit entries scoped to [vaultId] plus the cursor
  /// for the next page (or `null` when exhausted). [actions] is sent as a CSV
  /// of event-type wire strings for server-side narrowing.
  Future<AuditLogModelPage> listVaultLogs(
    String vaultId, {
    List<String> actions = const [],
    String? agentId,
    String? userId,
    String? entryId,
    DateTime? from,
    DateTime? to,
    String? cursor,
    int pageSize = 50,
  }) {
    final actionsCsv = actions.isEmpty ? null : actions.join(',');
    return _list('/api/vaults/$vaultId/audit-logs', <String, dynamic>{
      'actions': ?actionsCsv,
      'agentId': ?agentId,
      'userId': ?userId,
      'entryId': ?entryId,
      'from': ?from?.toUtc().toIso8601String(),
      'to': ?to?.toUtc().toIso8601String(),
      'cursor': ?cursor,
      'pageSize': pageSize,
    });
  }

  /// `GET /api/audit-logs`
  ///
  /// Returns one page of org-wide audit entries (every vault the caller can
  /// see) plus the next-page cursor. [actions] is sent as a CSV of event-type
  /// wire strings.
  Future<AuditLogModelPage> listOrgLogs({
    List<String> actions = const [],
    String? vaultId,
    String? agentId,
    String? userId,
    String? entryId,
    DateTime? from,
    DateTime? to,
    String? cursor,
    int pageSize = 50,
  }) {
    final actionsCsv = actions.isEmpty ? null : actions.join(',');
    return _list('/api/audit-logs', <String, dynamic>{
      'eventType': ?actionsCsv,
      'vaultId': ?vaultId,
      'agentId': ?agentId,
      'userId': ?userId,
      'entryId': ?entryId,
      'from': ?from?.toUtc().toIso8601String(),
      'to': ?to?.toUtc().toIso8601String(),
      'cursor': ?cursor,
      'pageSize': pageSize,
    });
  }

  Future<AuditLogModelPage> _list(
    String path,
    Map<String, dynamic> queryParameters,
  ) async {
    final response = await _dio.get<Map<String, dynamic>>(
      path,
      queryParameters: queryParameters,
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
