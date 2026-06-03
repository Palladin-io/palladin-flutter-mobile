import 'package:dio/dio.dart';

import '../services/grant_crypto_service.dart';
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
  Future<List<PendingGrantModel>> listPendingGrants() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/dashboard/pending-grants',
    );
    final data = response.data;
    if (data == null) throw _emptyBody(response);
    final raw = (data['items'] as List<dynamic>? ?? const <dynamic>[]);
    return raw
        .map((e) => PendingGrantModel.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
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
    required String entryId,
    required GrantEnvelope envelope,
    String? expiresAt,
    int? queryLimit,
  }) async {
    final body = <String, dynamic>{
      'grantEntry': <String, dynamic>{
        'entryId': entryId,
        'reEncryptedBlob': envelope.reEncryptedBlob,
        'nonce': envelope.nonce,
        'agentWrappedDek': envelope.agentWrappedDek,
      },
      'expiresAt': ?expiresAt,
      'queryLimit': ?queryLimit,
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
    String? reason,
  }) async {
    final trimmed = reason?.trim();
    await _dio.put<void>(
      '/api/vaults/$vaultId/grants/$grantId/deny',
      data: <String, dynamic>{'reason': ?trimmed},
    );
  }

  DioException _emptyBody(Response<dynamic> response) => DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Empty response body',
      );
}
