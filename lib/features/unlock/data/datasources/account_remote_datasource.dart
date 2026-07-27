import 'package:dio/dio.dart';

import '../models/account_response.dart';
import '../models/identity_kdf_migration_request.dart';

/// Remote data source for the unlock flow.
///
/// Fetches the persisted account material (salt + encrypted private
/// key) from the .NET backend Identity module at `/api/account`.
class AccountRemoteDatasource {
  AccountRemoteDatasource(this._dio);

  final Dio _dio;

  /// Fetches the current user's account material.
  ///
  /// Returns an [AccountResponse] with base64-encoded salt and
  /// encrypted-private-key ciphertext so the client can derive the
  /// master key and decrypt the private key locally.
  Future<AccountResponse> getAccount() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/account');
    final data = response.data;
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Empty response body',
      );
    }
    return AccountResponse.fromJson(data);
  }

  /// Atomically commits a prepared KDF migration. A retry of the identical
  /// request is safe because the backend keys it by [request.migrationId].
  Future<void> migrateIdentityKdf(IdentityKdfMigrationRequest request) async {
    await _dio.post<dynamic>(
      '/api/account/kdf/migrations',
      data: request.toJson(),
    );
  }
}
